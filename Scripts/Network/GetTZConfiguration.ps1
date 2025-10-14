$WLSKeyPath = "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\ConsentStore\\location"
$NTPKeyPath = "SYSTEM\\CurrentControlSet\\Services\\W32Time\\Parameters"
$NTPServerKeyPath = "SYSTEM\\CurrentControlSet\\Services\\W32Time\\Parameters"

$reg = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')

$wlsregkey = $reg.OpenSubKey($WLSKeyPath)
$ntpregkey = $reg.OpenSubKey($NTPKeyPath)
$ntpserverregkey = $reg.OpenSubKey($NTPServerKeyPath)

$WLSStatus = $wlsregkey.GetValue('Value') -eq "Allow"
$NTPStatus = $ntpregkey.GetValue('Type') -eq "NTP"
$NTPServerStatus = $ntpserverregkey.GetValue('NtpServer') -eq "time.windows.com,0x9"

$TZAutoUpdate = Get-Service -Name tzautoupdate | Select-Object -Property StartType, Status

Write-Output "$($TZAutoUpdate.StartType)|$($TZAutoUpdate.Status)|$($WLSStatus)|$($NTPStatus)|$($NTPServerStatus)"