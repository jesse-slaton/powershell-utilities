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