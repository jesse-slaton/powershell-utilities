<#
.SYNOPSIS
    Reports the automatic time zone and NTP settings as one pipe-delimited line.

.DESCRIPTION
    Reads, from the 64-bit view of HKLM:
    - CapabilityAccessManager\ConsentStore\location Value (True when it is "Allow");
    - W32Time\Parameters Type (True when it is "NTP");
    - W32Time\Parameters NtpServer (True when it is exactly "time.windows.com,0x9");
    and the StartType and Status of the tzautoupdate service.

    Outputs one line in this form:
    <StartType>|<Status>|<LocationAllowed>|<TypeIsNTP>|<NtpServerMatches>
    where the last three fields are True or False. Changes nothing.

.EXAMPLE
    .\GetTZConfiguration.ps1

    Outputs a line such as <StartType>|<Status>|True|True|False.

.NOTES
    No admin rights needed. If one of the registry keys is missing, OpenSubKey returns
    nothing and the GetValue call on it fails with a "null-valued expression" error.
    That error stops only that statement, so the script continues: the matching field
    is empty and the line is still written. Works in Windows PowerShell 5.1 and PowerShell 7.
    EnableTimeZoneUpdate.ps1 and EnableNTPClient.ps1 change the settings it checks.
#>
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