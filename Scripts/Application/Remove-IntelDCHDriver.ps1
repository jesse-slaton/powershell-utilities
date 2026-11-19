<#
.SYNOPSIS
    Removes Intel display devices that use an OEM driver package and deletes those packages.

.DESCRIPTION
    Reads Win32_PnPSignedDriver and selects entries whose DeviceName contains 'Intel',
    whose InfName contains 'oem', and whose DeviceClass is DISPLAY. For each entry it
    runs, in order:

    - .\devcon.exe find =display <CompatID>
    - .\devcon.exe remove <CompatID>
    - pnputil.exe -f -d <InfName>

    devcon.exe is called with a path relative to the current folder, so it must be in
    that folder. Writes the output of those tools. Changes system state: the display
    device is removed and its driver package is force-deleted from the driver store.

.EXAMPLE
    .\Remove-IntelDCHDriver.ps1

    Run from a folder that also contains devcon.exe.

.NOTES
    Requires administrator rights and devcon.exe (Windows Driver Kit) in the current
    folder. The display may switch to a basic display driver until a driver is installed
    again.
#>
#Get-Service -DisplayName "*Intel(R) HD Graphics Control Panel Service*" | Stop-Service 

$x = Get-CimInstance -Namespace root/CIMV2 -ClassName Win32_PnPSignedDriver `
| Where-Object { $_.DeviceName -like "*Intel*" -and $_.InfName -like "*oem*" -and $_.DeviceClass -eq "DISPLAY" } 

foreach ($InfName in $x) { 
    .\devcon.exe find =display $InfName.CompatID
    .\devcon.exe remove $InfName.CompatID
    pnputil.exe -f -d $InfName.InfName
}  