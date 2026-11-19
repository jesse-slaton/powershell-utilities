<#
.SYNOPSIS
    Intended to re-register Paint 3D, Calculator, Store and Photos for all users when they are missing.

.DESCRIPTION
    The if test pipes Get-AppxPackage -AllUsers to Select-Object with the four package
    names as property names. Those properties do not exist on package objects, so the
    result is empty only when no AppX packages are installed at all. On a normal
    system the test is false and the script does nothing.

    When the block does run, it re-registers Microsoft.Paint3D,
    Microsoft.WindowsCalculator, Microsoft.WindowsStore and Microsoft.Windows.Photos
    for each installed copy found by Get-AppxPackage -AllUsers, using
    Add-AppxPackage -DisableDevelopmentMode -Register on its AppXManifest.xml.
    Produces no output of its own.

.EXAMPLE
    & '.\Fix Whitelisted Apps-Sensor.ps1'

    Runs the check and, if it passes, re-registers the four apps.

.NOTES
    Requires administrator rights (-AllUsers). Uses the Appx cmdlets, so run it in
    Windows PowerShell 5.1. Despite the -Sensor name it changes the system when the
    block runs.
#>
If (!(Get-AppxPackage -AllUsers | Select Microsoft.Paint3D, Microsoft.WindowsCalculator, Microsoft.WindowsStore, Microsoft.Windows.Photos)) {
    
        #Credit to abulgatz for these 4 lines of code
        Get-AppxPackage -allusers Microsoft.Paint3D | Foreach {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"}
        Get-AppxPackage -allusers Microsoft.WindowsCalculator | Foreach {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"}
        Get-AppxPackage -allusers Microsoft.WindowsStore | Foreach {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"}
        Get-AppxPackage -allusers Microsoft.Windows.Photos | Foreach {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"} 
    } 
