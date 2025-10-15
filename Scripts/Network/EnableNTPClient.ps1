# Set the time server to time.windows.com
Set-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters -Name NtpServer -Value "time.windows.com,0x9" -Type String

# Configure the time service to start automatically and sync every 15 minutes
Set-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient -Name SpecialPollInterval -Value 900 -Type DWORD
Set-Service -Name w32time -StartupType Automatic
