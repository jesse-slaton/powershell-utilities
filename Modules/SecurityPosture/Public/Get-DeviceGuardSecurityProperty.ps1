function Get-DeviceGuardSecurityProperty {
    <#
    .SYNOPSIS
        Reports which Device Guard security properties are available or required on this computer.

    .DESCRIPTION
        Reads AvailableSecurityProperties or RequiredSecurityProperties (chosen by -Property)
        from Win32_DeviceGuard and returns one object with a Boolean per security property, in
        this order: Hypervisor, SecureBoot, DmaProtection, SecureMemoryOverwrite,
        NxProtections, SmmMitigations. A property is True when the CIM array contains its
        value (1 to 6). With -AsString the same flags are returned as one line of True/False
        values joined by '|', in the same order.

        On an operating system older than Windows 10 (version 10.0) Win32_DeviceGuard does not
        exist: the function writes a warning and returns nothing, or returns 'N/A' with
        -AsString. If Win32_DeviceGuard or Win32_OperatingSystem cannot be read, it writes a
        non-terminating error and returns nothing. Read-only.

        Replaces Scripts/Security/DGAvailableSecurityProperties.ps1 (-Property Available) and
        Scripts/Security/DGRequiredSecurityProperties.ps1 (-Property Required). Those scripts
        wrote the line with Write-Host and set the Nth flag when the array had an Nth element
        rather than when it held the value N; this function tests the value and writes to the
        pipeline. The script paths were removed without wrappers: no deployment tool depends on them.

    .PARAMETER Property
        Available reads AvailableSecurityProperties (what the hardware and firmware offer).
        Required reads RequiredSecurityProperties (what the configured policy requires).

    .PARAMETER AsString
        Return the legacy pipe-delimited line, for example True|True|False|False|True|False,
        instead of an object.

    .EXAMPLE
        Get-DeviceGuardSecurityProperty -Property Available

        Returns an object such as Hypervisor=True, SecureBoot=True, DmaProtection=False, ...

    .EXAMPLE
        Get-DeviceGuardSecurityProperty -Property Required -AsString

        Returns a line such as True|True|False|False|False|False, or N/A before Windows 10.

    .NOTES
        Windows 10 or later for Win32_DeviceGuard. No admin rights needed. Works in Windows
        PowerShell 5.1 and PowerShell 7 (CIM cmdlets). Part of the SecurityPosture module.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject], [string])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateSet('Available', 'Required')]
        [string]$Property,

        [switch]$AsString
    )

    try {
        $osVersion = Get-SecurityPostureOSVersion
    }
    catch {
        Write-Error -Message "Failed to read the operating system version: $($_.Exception.Message)" -Category ReadError
        return
    }
    if ($osVersion -lt [version]'10.0') {
        if ($AsString) { return 'N/A' }
        Write-Warning "Device Guard needs Windows 10 or later; this computer runs $osVersion."
        return
    }

    try {
        $deviceGuard = Get-DeviceGuardInstance
    }
    catch {
        Write-Error -Message "Failed to read Win32_DeviceGuard: $($_.Exception.Message)" -Category ReadError
        return
    }

    $values = @($deviceGuard."$($Property)SecurityProperties" | Where-Object { $null -ne $_ } | ForEach-Object { [uint32]$_ })
    $flags = [ordered]@{}
    $flagNames = [ordered]@{
        Hypervisor            = [uint32]1
        SecureBoot            = [uint32]2
        DmaProtection         = [uint32]3
        SecureMemoryOverwrite = [uint32]4
        NxProtections         = [uint32]5
        SmmMitigations        = [uint32]6
    }
    foreach ($name in $flagNames.Keys) {
        $flags[$name] = $values -contains $flagNames[$name]
    }

    if ($AsString) {
        return (@($flags.Values) -join '|')
    }
    [pscustomobject]$flags
}
