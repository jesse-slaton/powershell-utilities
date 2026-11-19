<#
.SYNOPSIS
    Shows the raw SMART attribute table for each disk that reports SMART data.

.DESCRIPTION
    If the session is not elevated, relaunches the script in a new elevated
    powershell.exe window (UAC prompt) and exits. When elevated, reads
    MSStorageDriver_FailurePredictData from the root\WMI namespace and, for each disk
    returned, splits the 512-byte VendorSpecific buffer into 12-byte attribute records
    starting at offset 2. Each record becomes an object with AttrID, StatusFlag1,
    StatusFlag2, AttrValue, WorstValue, Raws (6 raw bytes) and Reserved, and one table
    is written per disk with Format-Table. The loop walks the whole buffer, so it also
    emits rows for unused slots and for bytes past the 30-entry attribute table. The
    tables do not say which disk they belong to. Read-only.

.EXAMPLE
    .\Get-SMART.ps1

    From an elevated Windows PowerShell 5.1 session, prints one SMART attribute table
    per disk.

.NOTES
    Requires administrator rights (the script self-elevates). Requires Windows
    PowerShell 5.1: it uses Get-WmiObject, and the self-elevation always starts
    powershell.exe. When it self-elevates, the new window closes when the script ends,
    so run it from an elevated session to read the output. Only disks whose driver
    exposes SMART data through WMI are listed (typically ATA/SATA; often not NVMe or
    USB disks).
#>
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