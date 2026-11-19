<#
.SYNOPSIS
    Reads the Win32_DeviceGuard instance and defines lookup tables for its values; produces no output.

.DESCRIPTION
    Reads Win32_DeviceGuard (namespace root\Microsoft\Windows\DeviceGuard) with
    Get-CimInstance into $DGStatus, then defines hashtables (string keys "0", "1", ...)
    that name the values of AvailableSecurityProperties, RequiredSecurityProperties,
    CodeIntegrityPolicyEnforcementStatus, SecurityServicesConfigured,
    SecurityServicesRunning, VirtualizationBasedSecurityStatus and
    UsermodeCodeIntegrityPolicyEnforcementStatus.

    Nothing is tested or output: the script ends after defining the tables. Dot-source it
    to use $DGStatus and the tables in the current session. Read-only.

.EXAMPLE
    . .\TestDeviceGuardStatus.ps1
    $DGStatus.VirtualizationBasedSecurityStatus

    Dot-sources the script and shows the raw VBS status value it read.

.NOTES
    Requires Windows 10 or later (Win32_DeviceGuard). Works in Windows PowerShell 5.1
    and PowerShell 7 (uses Get-CimInstance).
#>
$DGStatus = Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard

$DGAvailableSecurityPropertiesHash = @{
    "0" = "None";
    "1" = "Hypervisor";
    "2" = "Secure Boot";
    "3" = "DMA Protection";
    "4" = "Secure Memory Overwrite";
    "5" = "NX Protections";
    "6" = "SMM Mitigations";
}

$DGRequiredSecurityPropertiesHash = @{
    "0" = "None";
    "1" = "Hypervisor";
    "2" = "Secure Boot";
    "3" = "DMA Protection";
    "4" = "Secure Memory Overwrite";
    "5" = "NX Protections";
    "6" = "SMM Mitigations";
}
$DGCodeIntegrityPolicyEnforcementStatusHash = @{
    "0" = "Off";
    "1" = "Audit Mode";
    "2" = "Enforcement Mode";
}

$DGSecurityServicesConfiguredHash = @{
    "0" = "None";
    "1" = "Credential Guard";
    "2" = "HypervisorEnforcedCodeIntegrity";
}

$DGSecurityServicesRunningHash = @{
    "0" = "None";
    "1" = "CredentialGuard";
    "2" = "Hypervisor Enforced Code Integrity";    
}

$DGVirtualizationBasedSecurityStatusHash = @{
    "0" = "Enabled";
    "1" = "Stopped";
    "2" = "Started";
}

$DGUsermodeCodeIntegrityPolicyEnforcementStatusHash = @{
    "0" = "Off";
    "1" = "Audit Mode";
    "2" = "Enforcement Mode";
}
