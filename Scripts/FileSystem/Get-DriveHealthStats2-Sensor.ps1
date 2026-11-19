<#
.SYNOPSIS
    Reports selected SMART attribute values from smartctl as one pipe-delimited line.

.DESCRIPTION
    For each fixed logical disk (Win32_LogicalDisk, DriveType 3) runs
    'smartctl -A <DriveLetter>' and parses the attribute table, adding the disk's
    FriendlyName and SerialNumber from Get-Partition | Get-Disk. The attribute list is
    reset for each drive, so only the last drive's attributes are kept. It then writes
    one line with Write-Host:

        <DriveLetter>|<FriendlyName>|<SerialNumber>|<5>|<187>|<188>|<197>|<198>

    where the numbered fields are the normalized VALUE column of SMART attributes 5, 187,
    188, 197 and 198 (empty when the attribute is not reported). Read-only.

.EXAMPLE
    .\Get-DriveHealthStats2-Sensor.ps1

    C:|<FriendlyName>|<SerialNumber>|<Value5>|<Value187>|<Value188>|<Value197>|<Value198>

.NOTES
    Written as a Tanium sensor. Requires smartctl.exe (smartmontools) on the PATH,
    administrator rights, and the Storage module (Get-Partition, Get-Disk). Uses the CIM
    cmdlets; runs on Windows PowerShell 5.1 and PowerShell 7.
#>
$Drives = (Get-CimInstance -Namespace root\cimv2 -ClassName Win32_LogicalDisk | ? {$_.DriveType -eq 3} )

Foreach ($Drive in $Drives) {
$smartctl = [string[]](smartctl -A $Drive.DeviceID)
$attributes=@()
foreach ($s in $smartctl) {
    if ($s -match '^\s*(\d+)\s+(\w+)\s+(\w+)\s+(\d+)\s+(\d+)\s+([\d-]+)\s+([\w-]+)\s+(\w+)\s+([\w-]+)\s+(\d+)') {
        $PSObj = new-object -Typename PSObject
        Add-Member -in $PSObj -m NoteProperty -Name 'DriveLetter' -Value ($Drive.DeviceID)
        Add-Member -in $PSObj -m NoteProperty -Name 'Manufacturer' -Value ((Get-Partition -DriveLetter $Drive.DeviceID.Substring(0,1) | Get-Disk).FriendlyName)
        Add-Member -in $PSObj -m NoteProperty -Name 'SerialNumber' -Value ((Get-Partition -DriveLetter $Drive.DeviceID.Substring(0,1) | Get-Disk).SerialNumber)
        Add-Member -in $PSObj -m NoteProperty -name 'ID' -value ([int]$matches[1])
        Add-Member -in $PSObj -m NoteProperty -name 'Name' -value $matches[2]
        #Add-Member -in $PSObj -m NoteProperty -name 'Flag' -value $matches[3]
        Add-Member -in $PSObj -m NoteProperty -name 'Value' -value ([int]$matches[4])
        #Add-Member -in $PSObj -m NoteProperty -name 'Worst' -value ([int]$matches[5])
        #Add-Member -in $PSObj -m NoteProperty -name 'Threshold' -value ([int]$matches[6])
        Add-Member -in $PSObj -m NoteProperty -name 'Type' -value $matches[7]
        #Add-Member -in $PSObj -m NoteProperty -name 'Updated' -value $matches[8]
        #Add-Member -in $PSObj -m NoteProperty -name 'WhenFailed' -value $matches[9]
        #Add-Member -in $PSObj -m NoteProperty -name 'Raw' -value ([int64]$matches[10])
        $attributes += $PSObj
        }
    }
}


ForEach ($attribute in $attributes) {
    $DriveLetter = $attribute.DriveLetter
    $Manufacturer = $attribute.Manufacturer
    $SerialNumber = $attribute.SerialNumber
    Switch ($attribute.id) {
    5 { $ID5 = $attribute.Value}
    187 { $ID187 = $attribute.Value}
    188 { $ID188 = $attribute.Value}
    197 { $ID197 = $attribute.Value}
    198 { $ID198 = $attribute.Value}
    }
    [String]$retVal =  $DriveLetter + "|" + $Manufacturer + "|" + $SerialNumber + "|" + $ID5 + "|" + $ID187 + "|" + $ID188 + "|" + $ID197 + "|" + $ID198
}

Write-Host $retVal