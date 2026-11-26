# BitLocker helpers. Every CIM and Active Directory call in Get-BitLockerVolumeStatus goes
# through these wrappers so tests can mock them on any OS.

function Get-BitLockerEncryptableVolume {
    <#
    .SYNOPSIS
        Reads the Win32_EncryptableVolume instances that have a drive letter.

    .DESCRIPTION
        Returns Win32_EncryptableVolume from root/CIMv2/Security/MicrosoftVolumeEncryption,
        filtered to volumes with a drive letter. Queries the local computer directly, or a
        remote one over WinRM when -ComputerName is given. Throws on failure. Private to
        SecurityPosture.

    .PARAMETER ComputerName
        A remote computer to query. Omit it for the local computer.

    .EXAMPLE
        Get-BitLockerEncryptableVolume

    .EXAMPLE
        Get-BitLockerEncryptableVolume -ComputerName PC01

    .NOTES
        Administrator rights (the class is readable only by administrators). Read-only.
    #>
    [CmdletBinding()]
    param([string]$ComputerName)

    $target = @{}
    if ($ComputerName) { $target.ComputerName = $ComputerName }
    Get-CimInstance -Namespace 'root/CIMv2/Security/MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume -Filter 'DriveLetter IS NOT NULL' -ErrorAction Stop @target
}

function Get-BitLockerEncryptionPercentage {
    <#
    .SYNOPSIS
        Returns the encryption percentage of a volume that is converting or paused.

    .DESCRIPTION
        Calls the GetConversionStatus method of a Win32_EncryptableVolume instance and returns
        its EncryptionPercentage. Throws on failure. Private to SecurityPosture.

    .PARAMETER Volume
        The Win32_EncryptableVolume CIM instance.

    .EXAMPLE
        Get-BitLockerEncryptionPercentage -Volume $volume

    .NOTES
        Administrator rights. Read-only.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Volume)

    (Invoke-CimMethod -InputObject $Volume -MethodName GetConversionStatus -ErrorAction Stop).EncryptionPercentage
}

function Get-BitLockerAdRecoveryInfo {
    <#
    .SYNOPSIS
        Lists the BitLocker recovery information objects stored in AD for one computer.

    .DESCRIPTION
        Finds the computer object by sAMAccountName (the NetBIOS name plus '$', unique in the
        domain) in the current domain, then returns one object per msFVE-RecoveryInformation
        child with VolumeId (Guid) and BackupDate (DateTime, from the object name). Each such
        entry is the escrowed recovery key of its volume. Every search names the attributes it
        loads (distinguishedname for the computer; name and msfve-volumeguid for the entries),
        so no recovery password or other confidential attribute is ever requested. Throws if
        ComputerName is an IP address, if the computer is not found, or if AD cannot be
        reached. Private to SecurityPosture.

    .PARAMETER ComputerName
        The computer name. A domain suffix is dropped and the rest is cut to the 15-character
        NetBIOS name, which is what sAMAccountName holds. An IP address is rejected.

    .EXAMPLE
        Get-BitLockerAdRecoveryInfo -ComputerName PC01

    .NOTES
        A domain-joined computer and rights to list the recovery objects. Read-only. The
        lookup uses the same AD technique as Bill Stewart's Get-BitLockerRecovery.ps1; no
        code from it is carried over.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ComputerName)

    $address = $null
    if (($ComputerName -match '^\d{1,3}(\.\d{1,3}){3}$' -or $ComputerName -match ':') -and [System.Net.IPAddress]::TryParse($ComputerName, [ref]$address)) {
        throw "'$ComputerName' is an IP address; Active Directory recovery information is looked up by computer name, so the AD lookup was skipped."
    }
    $shortName = ($ComputerName -split '\.')[0]
    if ($shortName.Length -gt 15) { $shortName = $shortName.Substring(0, 15) }
    # RFC 4515 escaping, so a name cannot change the filter.
    $escaped = -join ($shortName.ToCharArray() | ForEach-Object {
            if ('\', '*', '(', ')', [char]0 -contains $_) { '\{0:x2}' -f [int]$_ } else { $_ }
        })
    $searcher = New-Object -TypeName System.DirectoryServices.DirectorySearcher
    $computerEntry = $null
    try {
        # An empty PropertiesToLoad makes AD return every attribute the caller may read, so
        # each search names its attributes before it runs.
        $searcher.Filter = "(&(objectCategory=computer)(sAMAccountName=$escaped`$))"
        $searcher.PropertiesToLoad.Clear()
        $null = $searcher.PropertiesToLoad.Add('distinguishedname')
        $computer = $searcher.FindOne()
        if ($null -eq $computer) { throw "Computer '$shortName' was not found in Active Directory." }

        $computerEntry = $computer.GetDirectoryEntry()
        $searcher.SearchRoot = $computerEntry
        $searcher.Filter = '(objectClass=msFVE-RecoveryInformation)'
        $searcher.PropertiesToLoad.Clear()
        $null = $searcher.PropertiesToLoad.AddRange([string[]]@('name', 'msfve-volumeguid'))
        $found = $searcher.FindAll()
        try {
            foreach ($result in $found) {
                ConvertFrom-BitLockerRecoveryEntry -Name ([string]$result.Properties['name'][0]) `
                    -VolumeGuid ([byte[]]$result.Properties['msfve-volumeguid'][0])
            }
        }
        finally { $found.Dispose() }
    }
    finally {
        if ($null -ne $computerEntry) { $computerEntry.Dispose() }
        $searcher.Dispose()
    }
}

function ConvertFrom-BitLockerRecoveryEntry {
    <#
    .SYNOPSIS
        Builds the recovery-information object for one msFVE-RecoveryInformation entry.

    .DESCRIPTION
        The entry name is '<backup time>{<recovery password id>}'. Returns an object with
        VolumeId (the Guid of the msFVE-VolumeGuid bytes, or $null when absent) and BackupDate
        (the local time parsed from the name, or $null when it does not parse). Private to
        SecurityPosture.

    .PARAMETER Name
        The name attribute of the entry.

    .PARAMETER VolumeGuid
        The msFVE-VolumeGuid attribute (16 bytes).

    .EXAMPLE
        ConvertFrom-BitLockerRecoveryEntry -Name '2026-01-02T03:04:05-08:00{...}' -VolumeGuid $bytes

    .NOTES
        None.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$Name,
        [AllowNull()][byte[]]$VolumeGuid
    )

    $backupDate = $null
    $parsed = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse(($Name -split '\{')[0], [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsed)) {
        $backupDate = $parsed.LocalDateTime
    }
    $volumeId = $null
    if ($VolumeGuid -and $VolumeGuid.Length -eq 16) { $volumeId = New-Object -TypeName Guid -ArgumentList (, $VolumeGuid) }
    [pscustomobject]@{
        VolumeId   = $volumeId
        BackupDate = $backupDate
    }
}
