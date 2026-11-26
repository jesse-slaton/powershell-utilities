function Get-DeviceGuardStatus {
    <#
    .SYNOPSIS
        Returns the names of the Device Guard available and required security properties.

    .DESCRIPTION
        Reads Win32_DeviceGuard and translates each value of AvailableSecurityProperties and
        RequiredSecurityProperties to its name (0 None, 1 Hypervisor, 2 Secure Boot,
        3 DMA Protection, 4 Secure Memory Overwrite, 5 NX Protections, 6 SMM Mitigations,
        7 MBEC/GMET, 8 APIC Virtualization; any other value becomes 'Unknown (<value>)'). Returns one object with the string
        arrays AvailableSecurityProperties and RequiredSecurityProperties. With -AsString it
        returns the legacy line '<available>|<required>', the names in each part separated by
        spaces. If Win32_DeviceGuard cannot be read (for example before Windows 10), it writes
        a non-terminating error and returns nothing. Read-only.

        Replaces Scripts/Security/Get-DeviceGuardStatus.ps1, which wrote the line with
        Write-Host and translated the required part with the available loop's last value.
        The script path was removed without a wrapper: no deployment tool depends on it.

    .PARAMETER AsString
        Return the legacy line, for example 'Hypervisor Secure Boot|Hypervisor', instead of
        an object.

    .EXAMPLE
        Get-DeviceGuardStatus

        Returns an object such as AvailableSecurityProperties = Hypervisor, Secure Boot and
        RequiredSecurityProperties = Hypervisor.

    .EXAMPLE
        Get-DeviceGuardStatus -AsString

        Returns a line such as 'Hypervisor Secure Boot DMA Protection|Hypervisor'.

    .NOTES
        Windows 10 or later for Win32_DeviceGuard. No admin rights needed. Works in Windows
        PowerShell 5.1 and PowerShell 7 (CIM cmdlets). Part of the SecurityPosture module.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject], [string])]
    param(
        [switch]$AsString
    )

    try {
        $deviceGuard = Get-DeviceGuardInstance
    }
    catch {
        Write-Error -Message "Failed to read Win32_DeviceGuard: $($_.Exception.Message)" -Category ReadError
        return
    }

    [string[]]$available = @(ConvertTo-DeviceGuardPropertyName -Value $deviceGuard.AvailableSecurityProperties)
    [string[]]$required = @(ConvertTo-DeviceGuardPropertyName -Value $deviceGuard.RequiredSecurityProperties)

    if ($AsString) {
        return ('{0}|{1}' -f ($available -join ' '), ($required -join ' '))
    }
    [pscustomobject]@{
        AvailableSecurityProperties = $available
        RequiredSecurityProperties  = $required
    }
}
