<#
.SYNOPSIS
    Writes the names of the Device Guard available and required security properties as one line.

.DESCRIPTION
    Reads Win32_DeviceGuard (namespace root\Microsoft\Windows\DeviceGuard) with
    Get-CimInstance. Each value in AvailableSecurityProperties is translated to a name
    (0 None, 1 Hypervisor, 2 Secure Boot, 3 DMA Protection, 4 Secure Memory Overwrite,
    5 NX Protections, 6 SMM Mitigations); values outside 0-6 have no name in the
    table. The names are written with Write-Host as "<available>|<required>", with the
    names in each part separated by spaces.

    The required part does not translate RequiredSecurityProperties: its loop looks up
    $Property (the last value of the available loop) instead of its own loop variable,
    so it repeats that one name once per required property. The script also defines
    lookup tables for code integrity, security services and VBS status that it does not
    use. Output goes to the information stream (Write-Host), not the pipeline.
    Read-only.

.EXAMPLE
    .\Get-DeviceGuardStatus.ps1

    Writes a line in the form <available names>|<required names>.

.NOTES
    Requires Windows 10 or later (Win32_DeviceGuard). Works in Windows PowerShell 5.1
    and PowerShell 7 (uses Get-CimInstance).
#>
$DGStatus = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard

$DGAvailableSecurityPropertiesHash = @{
    [uint32]0 = "None";
    [uint32]1 = "Hypervisor"
    [uint32]2 = "Secure Boot";
    [uint32]3 = "DMA Protection";
    [uint32]4 = "Secure Memory Overwrite";
    [uint32]5 = "NX Protections";
    [uint32]6 = "SMM Mitigations";
}

$DGRequiredSecurityPropertiesHash = @{
    [uint32]0 = "None";
    [uint32]1 = "Hypervisor";
    [uint32]2 = "Secure Boot";
    [uint32]3 = "DMA Protection";
    [uint32]4 = "Secure Memory Overwrite";
    [uint32]5 = "NX Protections";
    [uint32]6 = "SMM Mitigations";
}
$DGCodeIntegrityPolicyEnforcementStatusHash = @{
    [uint32]0 = "Off";
    [uint32]1 = "Audit Mode";
    [uint32]2 = "Enforcement Mode";
}

$DGSecurityServicesConfiguredHash = @{
    [uint32]0 = "None";
    [uint32]1 = "Credential Guard";
    [uint32]2 = "HypervisorEnforcedCodeIntegrity";
}

$DGSecurityServicesRunningHash = @{
    [uint32]0 = "None";
    [uint32]1 = "CredentialGuard";
    [uint32]2 = "Hypervisor Enforced Code Integrity";    
}

$DGVirtualizationBasedSecurityStatusHash = @{
    [uint32]0 = "Enabled";
    [uint32]1 = "Stopped";
    [uint32]2 = "Started";
}

$DGUsermodeCodeIntegrityPolicyEnforcementStatusHash = @{
    [uint32]0 = "Off";
    [uint32]1 = "Audit Mode";
    [uint32]2 = "Enforcement Mode";
}

$ASP = Foreach ($Property in $DGStatus.AvailableSecurityProperties) { $DGAvailableSecurityPropertiesHash[$Property] }
$RSP = Foreach ($Property2 in $DGStatus.RequiredSecurityProperties) { $DGRequiredSecurityPropertiesHash[$Property] }
Write-Host "$ASP|$RSP"