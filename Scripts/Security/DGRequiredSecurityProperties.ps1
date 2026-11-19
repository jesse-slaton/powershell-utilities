<#
.SYNOPSIS
    Writes a pipe-delimited True/False line for the Device Guard required security properties.

.DESCRIPTION
    Reads the operating system version from Win32_OperatingSystem. On versions below 10.0
    it writes "N/A". Otherwise it reads RequiredSecurityProperties from Win32_DeviceGuard
    (namespace root\Microsoft\Windows\DeviceGuard) and writes six True/False values
    joined by "|", in this order: Hypervisor, Secure Boot, DMA Protection, Secure Memory
    Overwrite, NX Protections, SMM Mitigations.

    The Nth value is True when the RequiredSecurityProperties array has an element at
    position N (index N-1), not when it contains the value N. So the result reflects how
    many properties are reported, not which ones. Output is written with Write-Host
    (the information stream), not to the pipeline. Read-only.

.EXAMPLE
    .\DGRequiredSecurityProperties.ps1

    Writes a line such as True|True|True|False|False|False.

.NOTES
    Runs on Windows PowerShell 5.1 and PowerShell 7 (uses the CIM cmdlets). Requires
    Windows 10 or later for Win32_DeviceGuard. Writes a single
    pipe-delimited line. DGAvailableSecurityProperties.ps1 does the same
    for AvailableSecurityProperties.
#>
$OSVer = (Get-CimInstance -ClassName Win32_OperatingSystem -Namespace root\cimv2).Version
$Seedval = "False"
If ([System.Version]$OSVer -lt [System.Version]'10.0.00000') { Write-Host 'N/A' }
Else {
    $DGStatus = Get-CimInstance `
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
