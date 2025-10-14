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
