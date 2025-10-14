If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
{
  # Relaunch as an elevated process:
  Start-Process powershell.exe "-File",('"{0}"' -f $MyInvocation.MyCommand.Path) -Verb RunAs
  exit
}

$smart = Get-WmiObject -Namespace root\WMI -Class MSStorageDriver_FailurePredictData
if ($smart.VendorSpecific.Length -gt 0) {
    $smart = @($smart)
}
for ($n = 0; $n -lt $smart.Length; $n++) {
    $result = @()
    for ($i = 2; $i -lt $smart[$n].VendorSpecific.Length; $i += 12) {
        $result += [pscustomobject] @{
            AttrID = $smart[$n].VendorSpecific[$i];
            StatusFlag1 = $smart[$n].VendorSpecific[$i+1];
            StatusFlag2 = $smart[$n].VendorSpecific[$i+2];
            AttrValue = $smart[$n].VendorSpecific[$i+3];
            WorstValue = $smart[$n].VendorSpecific[$i+4];
            Raws = $smart[$n].VendorSpecific[($i+5)..($i+10)];
            Reserved = $smart[$n].VendorSpecific[$i+11];
        }
    }
    $result|Format-Table
}