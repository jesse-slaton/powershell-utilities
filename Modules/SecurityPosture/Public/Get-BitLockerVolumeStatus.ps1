function Get-BitLockerVolumeStatus {
    <#
    .SYNOPSIS
        Reports BitLocker status per volume, joined with the recovery information backed up to Active Directory.

    .DESCRIPTION
        Reads Win32_EncryptableVolume for every volume with a drive letter and returns one
        object per volume, sorted by drive letter, with: ComputerName, DriveLetter,
        ProtectionStatus (Unprotected, Protected or Unknown), ConversionStatus (Fully
        Decrypted, Fully Encrypted, Encryption in Progress, Decryption in Progress,
        Encryption Paused, Decryption Paused), EncryptionPercentage (only while converting
        or paused), VolumeId, and from Active Directory BackupDate (the newest
        msFVE-RecoveryInformation entry for that volume) and RecoveryKeyEscrowed.

        RecoveryKeyEscrowed is True when Active Directory holds at least one
        msFVE-RecoveryInformation entry for the volume (each entry is an escrowed recovery
        key), False when the lookup succeeded and the caller can see no entry for it, and
        empty when the lookup failed or the volume has no VolumeId. The recovery password
        itself is never requested. If the Active Directory lookup fails (for example on a
        workgroup computer, or when ComputerName is an IP address), the function writes a
        non-terminating error and still returns the volumes, with the AD columns empty. If
        the volumes cannot be read, it writes a non-terminating error and returns nothing.
        Read-only.

        Replaces Scripts/Security/BitlockerLocalAdStatusReport.ps1, which printed a
        '|'-delimited CSV. The output is not the same: the columns map as Computer Name to
        ComputerName, Drive Letter to DriveLetter, Volume ID to VolumeId, Backup Date to
        BackupDate and Has Password to RecoveryKeyEscrowed. The old Protection Status
        (True, False or Unknown; for an unprotected volume that was converting, followed by
        the conversion status and percentage) is now three columns: ProtectionStatus
        (Protected, Unprotected or Unknown), ConversionStatus and EncryptionPercentage.
        ConvertTo-Csv -Delimiter '|' gives a '|'-delimited CSV of these columns; it quotes
        every value, where the old script wrote none (PowerShell 7 accepts -UseQuotes Never).
        The script path was removed without a wrapper: no deployment tool depends on it.

    .PARAMETER ComputerName
        The computer to report on. Defaults to this computer; '.' and 'localhost' also mean
        this computer, which is queried directly. Another name is queried over WinRM.

    .EXAMPLE
        Get-BitLockerVolumeStatus

        Reports every lettered volume of this computer.

    .EXAMPLE
        Get-BitLockerVolumeStatus -ComputerName PC01 | ConvertTo-Csv -Delimiter '|' -NoTypeInformation

        Reports PC01 as '|'-delimited CSV with the columns above.

    .NOTES
        Administrator rights (Win32_EncryptableVolume), WinRM for a remote computer, and a
        domain-joined computer with rights to list its BitLocker recovery objects for the AD
        columns. Works in Windows PowerShell 5.1 and PowerShell 7. Part of the SecurityPosture
        module.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName = [Environment]::MachineName
    )

    if ($ComputerName -in @('.', 'localhost')) { $ComputerName = [Environment]::MachineName }
    $remote = @{}
    if ($ComputerName -ne [Environment]::MachineName) { $remote.ComputerName = $ComputerName }

    try {
        $volumes = @(Get-BitLockerEncryptableVolume @remote)
    }
    catch {
        Write-Error -Message "Failed to read the BitLocker volumes of ${ComputerName}: $($_.Exception.Message)" -Category ReadError -TargetObject $ComputerName
        return
    }

    $recovery = @()
    $adRead = $false
    try {
        $recovery = @(Get-BitLockerAdRecoveryInfo -ComputerName $ComputerName)
        $adRead = $true
    }
    catch {
        Write-Error -Message "Failed to read the BitLocker recovery information of $ComputerName from Active Directory: $($_.Exception.Message)" -Category ReadError -TargetObject $ComputerName
    }

    $protection = @{ 0 = 'Unprotected'; 1 = 'Protected'; 2 = 'Unknown' }
    $conversion = @{
        0 = 'Fully Decrypted'; 1 = 'Fully Encrypted'; 2 = 'Encryption in Progress'
        3 = 'Decryption in Progress'; 4 = 'Encryption Paused'; 5 = 'Decryption Paused'
    }

    $rows = foreach ($volume in $volumes) {
        # Cast to [int]: CIM returns UInt32, which never matches an Int32 hashtable key.
        $conversionCode = [int]$volume.ConversionStatus
        $percentage = $null
        if ($conversionCode -ge 2 -and $conversionCode -le 5) {
            try { $percentage = Get-BitLockerEncryptionPercentage -Volume $volume }
            catch { Write-Warning "Could not read the encryption percentage of $($volume.DriveLetter): $($_.Exception.Message)" }
        }

        $volumeId = $null
        $parsedId = [guid]::Empty
        if ([guid]::TryParse([string]$volume.PersistentVolumeID, [ref]$parsedId)) { $volumeId = $parsedId }
        $backup = $null
        $escrowed = $null
        if ($null -ne $volumeId -and $adRead) {
            $backup = $recovery | Where-Object { $_.VolumeId -eq $volumeId } | Sort-Object -Property BackupDate -Descending | Select-Object -First 1
            $escrowed = $null -ne $backup
        }

        [pscustomobject]@{
            ComputerName         = $ComputerName
            DriveLetter          = $volume.DriveLetter
            ProtectionStatus     = $protection[[int]$volume.ProtectionStatus]
            ConversionStatus     = $conversion[$conversionCode]
            EncryptionPercentage = $percentage
            VolumeId             = $volumeId
            BackupDate           = $(if ($backup) { $backup.BackupDate })
            RecoveryKeyEscrowed  = $escrowed
        }
    }
    $rows | Sort-Object -Property DriveLetter
}
