<#
.SYNOPSIS
    Removes a list of built-in and sponsored AppX apps, then removes every AppX package that is not on a short keep list.

.DESCRIPTION
    Runs in two passes.

    Pass 1: for each name pattern in $AppXApps (Bing News, Get Help, Xbox apps, Zune
    Music and Video, Skype, Mail and Calendar, and sponsored apps such as Candy Crush,
    Spotify and Twitter), removes the matching package for the current user, for all
    users (Remove-AppxPackage -AllUsers), and from the provisioned image
    (Remove-AppxProvisionedPackage -Online). Errors in this pass are suppressed.

    Pass 2: lists the packages of all users (Get-AppxPackage -AllUsers) and of the
    current user, and pipes those whose name does NOT match the $WhitelistedApps regex
    (Paint 3D, Calculator, Store, Photos, Ubuntu on Windows, some Xbox overlay and
    identity components, Sticky Notes and MS Paint) to Remove-AppxPackage without
    -AllUsers, so the removal applies to the user running the script. It also removes
    every provisioned package not on that allowlist (Remove-AppxProvisionedPackage -Online),
    which keeps those apps from being installed for new user profiles. This pass
    goes far beyond the list in pass 1 and does not suppress errors, so packages that
    cannot be removed produce error records.

    Writes a Verbose message per pattern in pass 1 (shown only when
    $VerbosePreference is Continue). Produces no other output.

.EXAMPLE
    & '.\Debloat Windows.ps1'

    Removes the listed apps for all users and from the provisioned image, then removes
    every AppX package not on the allowlist for the current user and from the provisioned
    image.

.NOTES
    Requires administrator rights (-AllUsers and -Online). Uses the Appx and DISM
    cmdlets, so run it in Windows PowerShell 5.1. Changes are destructive; removed
    provisioned packages are not reinstalled for new users. Revert Changes.ps1 only
    re-registers packages that are still installed.
#>
$AppXApps = @(

        #Unnecessary Windows 10 AppX Apps
        "*Microsoft.BingNews*"
        "*Microsoft.GetHelp*"
        "*Microsoft.Getstarted*"
        "*Microsoft.Messaging*"
        "*Microsoft.Microsoft3DViewer*"
        "*Microsoft.MicrosoftOfficeHub*"
        "*Microsoft.MicrosoftSolitaireCollection*"
        "*Microsoft.NetworkSpeedTest*"
        "*Microsoft.Office.Sway*"
        "*Microsoft.OneConnect*"
        "*Microsoft.People*"
        "*Microsoft.Print3D*"
        "*Microsoft.SkypeApp*"
        "*Microsoft.WindowsAlarms*"
        "*Microsoft.WindowsCamera*"
        "*microsoft.windowscommunicationsapps*"
        "*Microsoft.WindowsFeedbackHub*"
        "*Microsoft.WindowsMaps*"
        "*Microsoft.WindowsSoundRecorder*"
        "*Microsoft.Xbox.TCUI*"
        "*Microsoft.XboxApp*"
        "*Microsoft.XboxGameOverlay*"
        "*Microsoft.XboxIdentityProvider*"
        "*Microsoft.XboxSpeechToTextOverlay*"
        "*Microsoft.ZuneMusic*"
        "*Microsoft.ZuneVideo*"

        #Sponsored Windows 10 AppX Apps
        #Add sponsored/featured apps to remove in the "*AppName*" format
        "*EclipseManager*"
        "*ActiproSoftwareLLC*"
        "*AdobeSystemsIncorporated.AdobePhotoshopExpress*"
        "*Duolingo-LearnLanguagesforFree*"
        "*PandoraMediaInc*"
        "*CandyCrush*"
        "*Wunderlist*"
        "*Flipboard*"
        "*Twitter*"
        "*Facebook*"
        "*Spotify*"

        #Optional: Typically not removed but you can if you need to for some reason
        #"*Microsoft.Advertising.Xaml_10.1712.5.0_x64__8wekyb3d8bbwe*"
        #"*Microsoft.Advertising.Xaml_10.1712.5.0_x86__8wekyb3d8bbwe*"
        #"*Microsoft.BingWeather*"
        #"*Microsoft.MSPaint*"
        #"*Microsoft.MicrosoftStickyNotes*"
        #"*Microsoft.Windows.Photos*"
        #"*Microsoft.WindowsCalculator*"
        #"*Microsoft.WindowsStore*"
    )
    foreach ($App in $AppXApps) {
        Write-Verbose -Message ('Removing Package {0}' -f $App)
        Get-AppxPackage -Name $App | Remove-AppxPackage -ErrorAction SilentlyContinue
        Get-AppxPackage -Name $App -AllUsers | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
        Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $App | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    }
    
    #Removes AppxPackages
    #Credit to /u/GavinEke for a modified version of my whitelist code
    [regex]$WhitelistedApps = 'Microsoft.Paint3D|Microsoft.WindowsCalculator|Microsoft.WindowsStore|Microsoft.Windows.Photos|CanonicalGroupLimited.UbuntuonWindows|Microsoft.XboxGameCallableUI|Microsoft.XboxGamingOverlay|Microsoft.Xbox.TCUI|Microsoft.XboxGamingOverlay|Microsoft.XboxIdentityProvider|Microsoft.MicrosoftStickyNotes|Microsoft.MSPaint*'
    Get-AppxPackage -AllUsers | Where-Object {$_.Name -NotMatch $WhitelistedApps} | Remove-AppxPackage
    Get-AppxPackage | Where-Object {$_.Name -NotMatch $WhitelistedApps} | Remove-AppxPackage
    Get-AppxProvisionedPackage -Online | Where-Object {$_.PackageName -NotMatch $WhitelistedApps} | Remove-AppxProvisionedPackage -Online
