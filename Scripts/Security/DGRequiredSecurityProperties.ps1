$OSVer = (Get-WmiObject -ClassName Win32_OperatingSystem -Namespace root\cimv2).Version
$Seedval = "False"
If ([System.Version]$OSVer -lt [System.Version]'10.0.00000') { Write-Host 'N/A' }
Else {
    $DGStatus = Get-WmiObject `
        -Query "Select RequiredSecurityProperties from Win32_DeviceGuard" `
        -Namespace root\Microsoft\Windows\DeviceGuard

    $DGSecurityPropertiesHash = [ordered] @{
        [uint32]1 = "Hypervisor"
        [uint32]2 = "Secure Boot";
        [uint32]3 = "DMA Protection";
        [uint32]4 = "Secure Memory Overwrite";
        [uint32]5 = "NX Protections";
        [uint32]6 = "SMM Mitigations";
    }

    $DGRSP = @()
    $DGSecurityPropertiesHash.GetEnumerator() | ForEach-Object {
        If ($null -ne $DGStatus.RequiredSecurityProperties[($_.key - 1)]) {
            $Result = "True"
        }
        Else {
            $Result = $seedval
        }
        $obj = New-Object PSCustomObject -Property @{Name = $_.value; Result = "$Result" }
        $DGRSP += $obj
    }
    Write-Host "$($DGRSP.Result -join '|')"
}
