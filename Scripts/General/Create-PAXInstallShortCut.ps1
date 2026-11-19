#Version 1.5

<#     
       .SYNOPSIS
              Creates an "Install IBM PAX" Desktop shortcut that runs C:\DesktopSupportTools\PAX\install.cmd.
       .NOTES
       ===========================================================================
       Created with:       SAPIEN Technologies, Inc., PowerShell Studio 2014 v4.1.51
       Created on:         4/10/2014 3:02 PM
       Created by:         Jesse Slaton
       Organization:       MIG
       Filename:           
       ===========================================================================
              Prerequisites: Windows. The shortcut only works if
              C:\DesktopSupportTools\PAX\install.cmd has been staged separately.
              Run as the user who should get the shortcut. No admin rights needed
              to create it. Uses the WScript.Shell COM object.
       .DESCRIPTION
              Uses Powershell to create a Start Menu & Desktop shortcut icons.
              Only the Desktop shortcut is created: the script writes
              "Install IBM PAX.lnk" to the current user's Desktop folder (despite the
              variable name $PubDesktop, this is not the Public desktop) and creates
              no Start Menu shortcut. The shortcut runs
              $env:SystemRoot\System32\cmd.exe with the arguments
              /C C:\DesktopSupportTools\PAX\install.cmd, its working folder is
              System32, and its IconLocation is set to ",0". An existing
              shortcut with the same name is overwritten. The script does not check
              that install.cmd exists and produces no output.

       .EXAMPLE
              .\Create-PAXInstallShortCut.ps1

              Creates "Install IBM PAX.lnk" on the current user's Desktop.
#>

# DO NOT INCLUDE DRIVE, PROGRAM FILES, OR TRAILING BACKSLASH IN PATH
# BAD  EXAMPLE:  C:\Program Files\Application\Folder...
# GOOD EXAMPLE:  \Application\Folder...

$programpath = "$env:SystemRoot\System32"
$program = "cmd.exe"

$switches = ("/C C:\DesktopSupportTools\PAX\install.cmd")

$ShortcutName = "Install IBM PAX" + ".lnk"


# DO NOT EDIT ANYTHING BELOW THIS LINE
$dq = [Char]34
$bs = [Char]92
$PubDesktop = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)

$workingpath = $programpath
$FQProgram = ($dq + $workingpath + $bs + $program + $dq)
$argument = $switches


$WshShell = New-Object -comObject WScript.Shell
$DShortcut = $WshShell.CreateShortcut("$PubDesktop\$ShortcutName")
$DShortcut.TargetPath = "$FQProgram"
$DShortcut.Arguments = "$argument"
$DShortcut.IconLocation = ",0"
$DShortcut.WorkingDirectory = "$workingpath"
$DShortcut.Save()


# SAVING FOR FUTURE USE CASE
# IF AN EXISTING SHORTCUT EXISTS WITH THE SAME NAME; THEN USE THIS TO DELETE THE SHORTCUT FIRST
#Remove-Item "$PubDesktop\Taske Contact" -Force -Recurse -ErrorAction SilentlyContinue
#Remove-Item "$startmenupath\Taske Contact" -Force -Recurse -ErrorAction SilentlyContinue
