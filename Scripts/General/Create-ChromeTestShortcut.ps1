#Version 1.5

<#     
       .SYNOPSIS
              Creates a "Test Chrome" Desktop shortcut that starts Chrome with the audio service sandbox disabled.
       .NOTES
       ===========================================================================
       Created with:       SAPIEN Technologies, Inc., PowerShell Studio 2014 v4.1.51
       Created on:         9/24/2020 3:59 PM
       Created by:         Jesse Slaton
       Organization:       MIG
       Filename:           
       ===========================================================================
              Prerequisites: Windows, and 32-bit Google Chrome installed in
              C:\Program Files (x86)\Google\Chrome\Application (the path is
              hard-coded). Run as the user who should get the shortcut. No admin
              rights needed. Uses the WScript.Shell COM object, which is part of the
              Windows Script Host COM object model, not the VBScript engine; verified
              with the VBScript feature removed on Windows Server 2025, build
              26100.33828.
       .DESCRIPTION
              Creates one Desktop shortcut: the script writes
              "Test Chrome.lnk" to the current user's Desktop folder (despite the
              variable name $PubDesktop, this is not the Public desktop) and creates
              no Start Menu shortcut. The target is chrome.exe in
              C:\Program Files (x86)\Google\Chrome\Application, the working folder is
              that same folder, and the argument is
              --disable-features=AudioServiceSandbox. An existing shortcut with the
              same name is overwritten. Produces no output.

       .EXAMPLE
              .\Create-ChromeTestShortcut.ps1

              Creates "Test Chrome.lnk" on the current user's Desktop.
#>

# DO NOT INCLUDE DRIVE, PROGRAM FILES, OR TRAILING BACKSLASH IN PATH
# BAD  EXAMPLE:  C:\Program Files\Application\Folder...
# GOOD EXAMPLE:  \Application\Folder...

$ProgramPath = "C:\Program Files (x86)\Google\Chrome\Application\"
$Program = "chrome.exe"

$Switches = ("--disable-features=AudioServiceSandbox")

$ShortcutName = "Test Chrome.lnk"

# DO NOT EDIT ANYTHING BELOW THIS LINE
$dq = [Char]34
$bs = [Char]92
$PubDesktop = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)

$WorkingPath = $ProgramPath
$FQProgram = ($dq + $WorkingPath + $bs + $Program + $dq)
$Argument = $Switches


$WshShell = New-Object -comObject WScript.Shell
$DShortcut = $WshShell.CreateShortcut("$PubDesktop\$ShortcutName")
$DShortcut.TargetPath = "$FQProgram"
$DShortcut.Arguments = "$Argument"
$DShortcut.WorkingDirectory = "$WorkingPath"
$DShortcut.Save()

# SAVING FOR FUTURE USE CASE
# IF AN EXISTING SHORTCUT EXISTS WITH THE SAME NAME; THEN USE THIS TO DELETE THE SHORTCUT FIRST
#Remove-Item "$PubDesktop\Taske Contact" -Force -Recurse -ErrorAction SilentlyContinue
#Remove-Item "$startmenupath\Taske Contact" -Force -Recurse -ErrorAction SilentlyContinue