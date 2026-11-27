function Get-DriveHealth {
    <#
    .SYNOPSIS
        Returns selected SMART health attributes for each disk, read from WMI or from smartctl.

    .DESCRIPTION
        Returns one object per disk with DriveLetter, FriendlyName, SerialNumber, BusType,
        FirmwareVersion and the normalized values (not raw counts) of five SMART attributes:
        ReallocatedSectorsCount (5), ReportedUncorrectableErrors (187), CommandTimeout (188),
        CurrentPendingSectorCount (197) and UncorrectableSectorCount (198). An attribute the
        disk does not report is $null. A disk with no SMART data gets no object. Read-only.

        -Source Wmi (the default) lists disks with Get-Disk whose BusType is ATA, SATA, RAID,
        NVMe, USB or SAS, and parses each disk's MSStorageDriver_FailurePredictData instance
        from root\WMI. DriveLetter is $null on this path.

        -Source Smartctl runs smartctl -A for each fixed logical disk (Win32_LogicalDisk,
        DriveType 3) and reads the VALUE column of its attribute table. FriendlyName,
        SerialNumber, BusType and FirmwareVersion come from the disk that holds the drive
        letter.

        Merges Scripts/FileSystem/Get-DriveHealthStats.ps1 (the Wmi path) and
        Scripts/FileSystem/Get-DriveHealthStats2-Sensor.ps1 (the Smartctl path, now a thin
        wrapper around this function). Fixed on the way: each attribute is read from its own
        record (the old Wmi script put the last attribute's value in every column and carried
        values over from the previous disk), and every drive is reported (the old sensor kept
        only the last drive).

    .PARAMETER Source
        Wmi (the default) to read SMART data from root\WMI, or Smartctl to run smartctl.

    .EXAMPLE
        Get-DriveHealth | Format-Table -AutoSize

        Shows the SMART health attributes of every physical disk.

    .EXAMPLE
        Get-DriveHealth -Source Smartctl | Where-Object { $_.ReallocatedSectorsCount -lt 100 }

        Lists fixed drives whose reallocated-sectors value has dropped below 100.

    .NOTES
        Windows only. Requires administrator rights and the Storage module (Get-Disk,
        Get-Partition). -Source Smartctl also requires smartctl.exe (smartmontools) on PATH.
        Runs on Windows PowerShell 5.1 and PowerShell 7. Part of the StorageHealth module.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateSet('Wmi', 'Smartctl')]
        [string]$Source = 'Wmi'
    )

    function ConvertTo-DriveHealthRecord {
        param($DriveLetter, $Disk, [hashtable]$Values)
        [pscustomobject]@{
            DriveLetter                 = $DriveLetter
            FriendlyName                = $Disk.FriendlyName
            SerialNumber                = $Disk.SerialNumber
            BusType                     = $Disk.BusType
            FirmwareVersion             = $Disk.FirmwareVersion
            ReallocatedSectorsCount     = $Values[5]
            ReportedUncorrectableErrors = $Values[187]
            CommandTimeout              = $Values[188]
            CurrentPendingSectorCount   = $Values[197]
            UncorrectableSectorCount    = $Values[198]
        }
    }

    if ($Source -eq 'Wmi') {
        $smartData = @(Get-CimInstance -Namespace 'root\WMI' -ClassName MSStorageDriver_FailurePredictData -ErrorAction Stop)
        $busTypes = 'ATA', 'SATA', 'RAID', 'NVMe', 'USB', 'SAS'
        foreach ($disk in @(Get-Disk | Where-Object { $busTypes -contains "$($_.BusType)" })) {
            $instance = @("$($disk.Path)" -split '#')[2]
            if (-not $instance) { continue }
            $smart = @($smartData | Where-Object { "$($_.InstanceName)" -match [regex]::Escape($instance) }) | Select-Object -First 1
            if (-not $smart) { continue }
            $values = @{}
            foreach ($attribute in @(ConvertFrom-SmartVendorSpecific -VendorSpecific $smart.VendorSpecific)) {
                $values[[int]$attribute.AttrID] = [int]$attribute.AttrValue
            }
            if ($values.Count -eq 0) { continue }
            ConvertTo-DriveHealthRecord -DriveLetter $null -Disk $disk -Values $values
        }
        return
    }

    $pattern = '^\s*(\d+)\s+(\w+)\s+(\w+)\s+(\d+)\s+(\d+)\s+([\d-]+)\s+([\w-]+)\s+(\w+)\s+([\w-]+)\s+(\d+)'
    foreach ($drive in @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop)) {
        $letter = "$($drive.DeviceID)"
        $values = @{}
        foreach ($line in @(Invoke-Smartctl -Device $letter)) {
            if ("$line" -match $pattern) {
                $values[[int]$Matches[1]] = [int]$Matches[4]
            }
        }
        if ($values.Count -eq 0) { continue }
        $partition = Get-Partition -DriveLetter $letter.Substring(0, 1) -ErrorAction SilentlyContinue | Select-Object -First 1
        $disk = if ($partition) { Get-Disk -Number $partition.DiskNumber -ErrorAction SilentlyContinue }
        ConvertTo-DriveHealthRecord -DriveLetter $letter -Disk $disk -Values $values
    }
}
