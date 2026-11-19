<#
.SYNOPSIS
    If the tzautoupdate service is not already set to Automatic, sets it to Automatic, allows location access if it is denied, and starts the service.

.DESCRIPTION
    Does nothing (and outputs nothing) when the tzautoupdate service startup type is
    already Automatic. Otherwise it:
    - sets tzautoupdate to start automatically;
    - reads the Value entry under
      HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location;
      if it is "Deny", outputs "Location is disabled" and sets it to "Allow",
      otherwise outputs "Location is enabled";
    - starts the tzautoupdate service.

    Note that "Location is disabled" describes the state before the script changed it.

.EXAMPLE
    .\EnableTimeZoneUpdate.ps1

    Enables automatic time zone updates and system location access if they are not
    already on.

.NOTES
    Requires administrator rights. Allowing location access affects the whole device.
    Works in Windows PowerShell 5.1 and PowerShell 7. GetTZConfiguration.ps1 reports on
    these settings.
#>
# Check if tzautoupdate service is set to automatic start
if ((Get-Service -Name tzautoupdate).StartType -ne 'Automatic') {
    # Configure tzautoupdate service to start automatically
    Set-Service -Name tzautoupdate -StartupType Automatic
    
    # Enable location
    $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location\"
    $LocationSetting = (Get-ItemProperty -Path $RegPath -Name Value).Value
    If ($LocationSetting -eq "Deny") {
        Write-Output "Location is disabled"
        Set-ItemProperty -Path $RegPath -Name Value -Value "Allow"
    }
    Else {
        Write-Output "Location is enabled"
    }
    # Start tzautoupdate service
    Start-Service -Name tzautoupdate
}