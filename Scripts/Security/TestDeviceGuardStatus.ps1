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
