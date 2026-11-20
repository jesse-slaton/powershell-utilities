<#
.SYNOPSIS
    Creates "Manage Distribution Lists" shortcuts that open the Active Directory Find dialog.

.DESCRIPTION
    Deletes any existing "Manage Distribution Lists.lnk" and "DSQuery.lnk" from the Public
    desktop ($env:PUBLIC\Desktop) and the all-users Start Menu
    ($env:ProgramData\Microsoft\Windows\Start Menu\Programs), then creates
    "Manage Distribution Lists.lnk" in both places. Each shortcut runs
    %SYSTEMROOT%\System32\rundll32.exe with the arguments "dsquery,OpenQueryWindow"
    (the Find Users, Contacts, and Groups dialog) and uses icon 74 of
    c:\windows\system32\imageres.dll. The name, target, arguments and icon are set in
    variables at the top of the script. If saving a shortcut fails, the error record is
    written to the output; otherwise the script produces no output.

.EXAMPLE
    & '.\DSQuery Shortcut.ps1'

    Replaces the old DSQuery shortcuts with "Manage Distribution Lists" shortcuts for all
    users.

.NOTES
    Requires administrator rights (writes to the Public desktop and the all-users Start
    Menu). The dialog is only useful on a domain-joined computer. Uses the WScript.Shell
    COM object, so Windows only. The shortcut dependency is the Windows Script Host COM
    object model (WScript.Shell), not the VBScript engine; verified with the VBScript
    feature removed on Windows Server 2025, build 26100.33828.
#>

###Customize These Variables###
#Shortcut Program Path.  Environmental Variables Are allowed.
$Program = "%SYSTEMROOT%\System32\rundll32.exe"
#Shortcut Argument. Leave blank double quotes ("") If none are required.
$Arguments = " dsquery,OpenQueryWindow"
#Shortcut Icon.  Note that the .ico, .icl, .exe, or .dll must be in the %PATH%, otherwise you must explicity define the path.
$Icon = "c:\windows\system32\imageres.dll,74"
#Name of the shortcut.  Spaces are allowed.
$ShortcutName = "Manage Distribution Lists"
###DO NOT MODIFY!###
$PubDesktop = "$env:PUBLIC" + "\Desktop"
$StartMenuPath = "$env:ProgramData" + "\Microsoft\Windows\Start Menu\Programs"
$OldIcons = @("$PubDesktop\$ShortcutName.lnk","$StartMenuPath\$ShortcutName.lnk",`
    "$StartMenuPath\DSQuery.lnk", "$PubDesktop\DSQuery.lnk")

#Remove Existing Icons
ForEach ($OldIcon in $OldIcons) { Remove-Item -Force -Path $OldIcon -EA SilentlyContinue }
    
$WshShell = New-Object -comObject WScript.Shell

#Create All User Desktop Shortcut
$DShortcut = $WshShell.CreateShortcut("$PubDesktop\$ShortcutName.lnk")
$DShortcut.TargetPath = "$Program"
$DShortcut.Arguments = "$Arguments"
$DShortcut.IconLocation = "$Icon"
Try { $DShortcut.Save() }
Catch {$_}

#Create All User Start Menu Shortcut
$SShortcut = $WshShell.CreateShortcut("$StartMenuPath\$ShortcutName.lnk")
$SShortcut.TargetPath = "$Program"
$SShortcut.Arguments = "$Arguments"
$SShortcut.IconLocation = "$Icon"
Try { $SShortcut.Save() }
Catch {$_}
