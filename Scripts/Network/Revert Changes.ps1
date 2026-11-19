<#
.SYNOPSIS
    Re-registers installed AppX packages and reverses part of the privacy settings applied by Protect Privacy-Package.ps1.

.DESCRIPTION
    Re-registers every package returned by Get-AppxPackage -AllUsers from its
    AppXManifest.xml (Add-AppxPackage -DisableDevelopmentMode -Register, with -Verbose).
    Packages that were fully removed are not listed by Get-AppxPackage and so are not
    restored.

    Then, writing a status line to the output stream before each step, it sets:
    - AdvertisingInfo Enabled = 1 and Windows Search policy AllowCortana = 1 (HKLM),
      only if the keys exist.
    - Siuf\Rules PeriodInNanoSeconds = 1 (HKCU).
    - CloudContent DisableWindowsConsumerFeatures = 0 (HKLM policy).
    - Holographic FirstRunSucceeded = 1 (HKCU), only if the key exists.
    - PushNotifications NoTileApplicationNotification = 0 (HKCU policy).
    - AllowTelemetry = 1 under HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection.
    - PeopleBand = 1 and ContentDeliveryManager SystemPaneSuggestionsEnabled = 1 (HKCU).
    Missing keys are created except where noted. It re-enables the scheduled tasks
    XblGameSaveTaskLogon, XblGameSaveTask, Consolidator, UsbCeip, DmClient and
    DmClientOnScenarioDownload, and sets dmwappushservice and DiagTrack to Automatic
    and starts them.

    It does not revert the web search, Wi-Fi Sense, location, the other two
    DataCollection keys, or the other ContentDeliveryManager values.

.EXAMPLE
    & '.\Revert Changes.ps1'

    Re-registers installed apps and restores the settings listed above.

.NOTES
    Requires administrator rights (HKLM, -AllUsers, scheduled tasks and services).
    HKCU changes apply to the user the script runs as. Uses the Appx cmdlets, so run it
    in Windows PowerShell 5.1.
#>
#This function will revert the changes you made when running the Start-Debloat function.
        
    #This line reinstalls all of the bloatware that was removed
    Get-AppxPackage -AllUsers | ForEach {Add-AppxPackage -Verbose -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"} 
    
    #Tells Windows to enable your advertising information.    
    Write-Output "Re-enabling key to show advertisement information"
    $Advertising = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
    If (Test-Path $Advertising) {
        Set-ItemProperty $Advertising  Enabled -Value 1
    }
            
    #Enables Cortana to be used as part of your Windows Search Function
    Write-Output "Re-enabling Cortana to be used in your Windows Search"
    $Search = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
    If (Test-Path $Search) {
        Set-ItemProperty $Search  AllowCortana -Value 1 
    }
            
    #Re-enables the Windows Feedback Experience for sending anonymous data
    Write-Output "Re-enabling Windows Feedback Experience"
    $Period = "HKCU:\Software\Microsoft\Siuf\Rules"
    If (!(Test-Path $Period)) { 
        New-Item $Period
    }
    Set-ItemProperty $Period PeriodInNanoSeconds -Value 1 
    
    #Enables bloatware applications               
    Write-Output "Adding Registry key to allow bloatware apps to return"
    $registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    If (!(Test-Path $registryPath)) {
        New-Item $registryPath 
    }
    Set-ItemProperty $registryPath  DisableWindowsConsumerFeatures -Value 0 
        
    #Changes Mixed Reality Portal Key 'FirstRunSucceeded' to 1
    Write-Output "Setting Mixed Reality Portal value to 1"
    $Holo = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Holographic"
    If (Test-Path $Holo) {
        Set-ItemProperty $Holo  FirstRunSucceeded -Value 1 
    }
        
    #Re-enables live tiles
    Write-Output "Enabling live tiles"
    $Live = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications"
    If (!(Test-Path $Live)) {
        New-Item $Live 
    }
    Set-ItemProperty $Live  NoTileApplicationNotification -Value 0 
       
    #Re-enables data collection
    Write-Output "Re-enabling data collection"
    $DataCollection = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
    If (!(Test-Path $DataCollection)) {
        New-Item $DataCollection
    }
    Set-ItemProperty $DataCollection  AllowTelemetry -Value 1
        
    #Re-enables People Icon on Taskbar
    Write-Output "Enabling People icon on Taskbar"
    $People = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People"
    If (!(Test-Path $People)) {
        New-Item $People 
    }
    Set-ItemProperty $People  PeopleBand -Value 1 
    
    #Re-enables suggestions on start menu
    Write-Output "Enabling suggestions on the Start Menu"
    $Suggestions = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    If (!(Test-Path $Suggestions)) {
        New-Item $Suggestions
    }
    Set-ItemProperty $Suggestions  SystemPaneSuggestionsEnabled -Value 1 
        
    #Re-enables scheduled tasks that were disabled when running the Debloat switch
    Write-Output "Enabling scheduled tasks that were disabled"
    Get-ScheduledTask XblGameSaveTaskLogon | Enable-ScheduledTask 
    Get-ScheduledTask  XblGameSaveTask | Enable-ScheduledTask 
    Get-ScheduledTask  Consolidator | Enable-ScheduledTask 
    Get-ScheduledTask  UsbCeip | Enable-ScheduledTask 
    Get-ScheduledTask  DmClient | Enable-ScheduledTask 
    Get-ScheduledTask  DmClientOnScenarioDownload | Enable-ScheduledTask 

    Write-Output "Re-enabling and starting WAP Push Service"
    #Enable and start WAP Push Service
	Set-Service "dmwappushservice" -StartupType Automatic
    Start-Service "dmwappushservice"
    
    Write-Output "Re-enabling and starting the Diagnostics Tracking Service"
    #Enabling the Diagnostics Tracking Service
	Set-Service "DiagTrack" -StartupType Automatic
	Start-Service "DiagTrack"
