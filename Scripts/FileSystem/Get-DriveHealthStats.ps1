$Disks = Get-Disk | Where-Object -FilterScript {$_.BusType -in "ATA", "SATA", "RAID", "NVMe", "USB", "SAS"}
$Drives_Array = @()
ForEach ($Disk in $Disks) {
    $Instance = ($Disk.Path).split('#')[2]
    $smart = Get-CimInstance -Namespace root\WMI -ClassName MSStorageDriver_FailurePredictData | ? {$_.InstanceName -match $Instance}
    if ($smart.VendorSpecific.Length -gt 0) {
        $smart = @($smart)
    }
    for ($n = 0; $n -lt $smart.Length; $n++) {
        $result = @()
        for ($i = 2; $i -lt $smart[$n].VendorSpecific.Length; $i += 12) {
            $result += [pscustomobject] @{

                AttrID = $smart[$n].VendorSpecific[$i] ;
                StatusFlag1 = $smart[$n].VendorSpecific[$i+1];
                StatusFlag2 = $smart[$n].VendorSpecific[$i+2];
                AttrValue = $smart[$n].VendorSpecific[$i+3];
                WorstValue = $smart[$n].VendorSpecific[$i+4];
                Raws = $smart[$n].VendorSpecific[($i+5)..($i+10)];
                Reserved = $smart[$n].VendorSpecific[$i+11];
            }
        }
        $FriendlyName = $Disk.FriendlyName
        $SerialNumber = $Disk.SerialNumber
        $Bus_Type = $Disk.BusType
        $Firmware_Version = $Disk.FirmwareVersion
        ForEach ($r in $result) {
            Switch ($result.AttrID) {
                5 { if ($r.AttrValue.ToString() -eq $null) {$Reallocated_Sectors_Count = "NA"} else {$Reallocated_Sectors_Count = $r.AttrValue}}
                187 { if ($r.AttrValue.ToString() -eq $null) {$Reported_Uncorrectable_Errors = "NA"} else {$Reported_Uncorrectable_Errors = $r.AttrValue}}
                188 { if ($r.AttrValue.ToString() -eq $null) {$Command_Timeout = "NA"} else {$Command_Timeout = $r.AttrValue}}
                197 { if ($r.AttrValue.ToString() -eq $null) {$Current_Pending_Sector_Count ="NA"} else {$Current_Pending_Sector_Count = $r.AttrValue}}
                198 { if ($r.AttrValue.ToString() -eq $null) {$Uncorrectable_Sector_Count = "NA"} else {$Uncorrectable_Sector_Count = $r.AttrValue}}
            }
        }
        $Drives_Obj = [PSCustomObject]@{
		"Friendly Name"                = $FriendlyName
		"Serial Number"                = $SerialNumber
		"Bus Type"                     = $Bus_Type
		"Firmware Version"             = $Firmware_Version
		"Reallocated Sectors Count"    = $Reallocated_Sectors_Count
		"Reported Uncorrectable Errors"= $Reported_Uncorrectable_Errors
		"Command Timeout"              = $Command_Timeout
		"Current Pending Sector Count" = $Current_Pending_Sector_Count
		"Uncorrectable Sector Count"   = $Uncorrectable_Sector_Count
        }
        $Drives_Array += $Drives_Obj
    }    
}
$Drives_Array | ft -a