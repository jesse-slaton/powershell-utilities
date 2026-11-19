<#
.SYNOPSIS
    Points the Windows Time service at time.windows.com, sets a 15-minute poll interval, and sets the service to start automatically.

.DESCRIPTION
    Writes these registry values:
    - HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters NtpServer =
      "time.windows.com,0x9" (String)
    - HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient
      SpecialPollInterval = 900 (DWORD, seconds)
    Then sets the w32time service startup type to Automatic.

    It does not change the Parameters Type value, and it does not start, restart or
    resync the service, so the new settings take effect only after the service next
    reads its configuration (for example after a restart). Produces no output.

.EXAMPLE
    .\EnableNTPClient.ps1

    Applies the time server, poll interval and startup type.

.NOTES
    Requires administrator rights. Works in Windows PowerShell 5.1 and PowerShell 7.
    GetWindowsTimeSettings-Package.ps1 and GetTZConfiguration.ps1 report on these
    settings.
#>
# Set the time server to time.windows.com
Set-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters -Name NtpServer -Value "time.windows.com,0x9" -Type String

# Configure the time service to start automatically and sync every 15 minutes
Set-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient -Name SpecialPollInterval -Value 900 -Type DWORD
Set-Service -Name w32time -StartupType Automatic
