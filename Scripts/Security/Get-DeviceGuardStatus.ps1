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