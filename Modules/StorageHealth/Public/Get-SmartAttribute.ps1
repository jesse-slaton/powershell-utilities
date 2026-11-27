function Get-SmartAttribute {
    <#
    .SYNOPSIS
        Returns the raw SMART attribute records of each disk that reports SMART data.

    .DESCRIPTION
        Reads MSStorageDriver_FailurePredictData from the root\WMI namespace and, for each
        disk returned, parses its VendorSpecific buffer into SMART attribute records. Returns
        one object per attribute with InstanceName (the disk), AttrID, StatusFlag1,
        StatusFlag2, AttrValue (normalized value), WorstValue, Raws (the six raw bytes) and
        Reserved. Unused attribute slots and bytes past the 30-entry attribute table are
        skipped. Read-only.

        Formerly Scripts/System/Get-SMART.ps1, which wrote one unlabeled table per disk and
        relaunched itself elevated in powershell.exe (Windows PowerShell 5.1). A function
        cannot relaunch its caller, so this throws when the session is not elevated; start
        PowerShell with Run as administrator instead.

    .EXAMPLE
        Get-SmartAttribute | Format-Table -GroupBy InstanceName

        Shows one SMART attribute table per disk, labeled with the disk.

    .EXAMPLE
        Get-SmartAttribute | Where-Object AttrID -eq 194

        Returns the temperature attribute of each disk.

    .NOTES
        Windows only. Requires administrator rights. Only disks whose driver exposes SMART
        data through WMI are listed (typically ATA/SATA; often not NVMe or USB disks). Runs
        on Windows PowerShell 5.1 and PowerShell 7. Part of the StorageHealth module.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    if (-not (Test-IsAdministrator)) {
        throw 'Get-SmartAttribute requires an elevated session. Start PowerShell with Run as administrator.'
    }

    foreach ($disk in @(Get-CimInstance -Namespace 'root\WMI' -ClassName MSStorageDriver_FailurePredictData -ErrorAction Stop)) {
        foreach ($attribute in @(ConvertFrom-SmartVendorSpecific -VendorSpecific $disk.VendorSpecific)) {
            [pscustomobject]@{
                InstanceName = $disk.InstanceName
                AttrID       = $attribute.AttrID
                StatusFlag1  = $attribute.StatusFlag1
                StatusFlag2  = $attribute.StatusFlag2
                AttrValue    = $attribute.AttrValue
                WorstValue   = $attribute.WorstValue
                Raws         = $attribute.Raws
                Reserved     = $attribute.Reserved
            }
        }
    }
}
