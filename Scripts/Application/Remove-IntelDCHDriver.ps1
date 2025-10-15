#Get-Service -DisplayName "*Intel(R) HD Graphics Control Panel Service*" | Stop-Service 

$x = Get-CimInstance -Namespace root/CIMV2 -ClassName Win32_PnPSignedDriver `
| Where-Object { $_.DeviceName -like "*Intel*" -and $_.InfName -like "*oem*" -and $_.DeviceClass -eq "DISPLAY" } 

foreach ($InfName in $x) { 
    .\devcon.exe find =display $InfName.CompatID
    .\devcon.exe remove $InfName.CompatID
    pnputil.exe -f -d $InfName.InfName
}  