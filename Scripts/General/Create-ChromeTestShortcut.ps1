#Version 1.5

<#     
       .NOTES
       ===========================================================================
       Created with:       SAPIEN Technologies, Inc., PowerShell Studio 2014 v4.1.51
       Created on:         9/24/2020 3:59 PM
       Created by:         Jesse Slaton
       Organization:       MIG
       Filename:           
       ===========================================================================
       .DESCRIPTION
              Uses Powershell to create a Start Menu & Desktop shortcut icons.
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