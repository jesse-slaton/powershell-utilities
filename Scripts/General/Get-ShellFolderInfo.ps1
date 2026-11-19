<#
.SYNOPSIS
    Deletes shortcuts to Avaya CMS Supervisor versions other than R18 for the primary user and all users.

.DESCRIPTION
    Despite its name, this script removes shortcuts. It reads the Altiris Agent's
    basic inventory (the Altiris.BasicInventory COM object) to find the primary user
    from the "AeX AC Primary User" data class, translates that account to a SID, and
    reads the user's Desktop and Start Menu paths from
    HKEY_USERS\<SID>\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders
    (creating an HKU: PSDrive if one does not exist). It then searches those two
    folders plus the common Desktop and common Start Menu, recursively, for .lnk files
    whose target path contains "CMS Supervisor" but not "R18", and deletes them.

    Writes "Removed: <ShortcutName> removed." for each shortcut it deletes. When the
    HKU: drive is created, the new PSDrive object is also written to the output.

.EXAMPLE
    .\Get-ShellFolderInfo.ps1

    Removes old CMS Supervisor shortcuts and lists each one it removed.

.NOTES
    Requires the Altiris (Symantec Management) Agent with basic inventory data, and
    administrator rights (reads another user's registry hive and deletes from the
    common Desktop and Start Menu). The primary user's hive must be loaded under
    HKEY_USERS, which is normally only true while that user is logged on. Uses COM
    objects, so Windows only.
#>

#Query Altiris Agent's most recent basic inventory to determine the primary user account information
$BasicInventory = New-Object -ComObject Altiris.BasicInventory
[xml]$inventory = $BasicInventory.Inventory
$PrimaryUser = ($inventory.message.body.inventory.dataClass | `
        Where-Object {$_.name -eq 'AeX AC Primary User'}).data.childnodes.row

#Obtain SID for the Primary User Account
$UserName = New-Object System.Security.Principal.NTAccount($PrimaryUser.c2)
$SID = $UserName.Translate([System.Security.Principal.SecurityIdentifier]).value

#Enumerate Primary User's Shell Folders
If (!(Test-Path HKU:)) {
    New-PSDrive -PSProvider Registry -Name HKU -Root HKEY_USERS
}
$ShellFolders = Get-ItemProperty -Path "HKU:\$SID\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders"

# Array of the Primary User's Desktop and Start Menu shell folders, as well as the Common Desktop and Start Menu.
$FolderPaths = @(
    $ShellFolders.Desktop
    $ShellFolders.'Start Menu'
    [Environment]::GetFolderPath("CommonDesktopDirectory")
    [Environment]::GetFolderPath("CommonStartMenu")
)

#Recursively search each path to identify shortcuts to CMS Supervisor versions below R18 and delete them
foreach ($Path in $FolderPaths) {
    $WshShell = New-Object -comObject WScript.Shell
    $Files = Get-ChildItem -Path $Path -Filter *.lnk -Recurse
    foreach ($File in $Files) {
        $FilePath = $File.FullName
        $Shortcut = $WshShell.CreateShortcut($FilePath)
        $Target = $Shortcut.TargetPath
        If ($Target -match 'CMS Supervisor' -and $Target -notmatch 'R18') {
            try {
                Remove-Item -Path $FilePath
                Write-Output "Removed: $($File.BaseName) removed."
            }
            catch {
                Write-Output "ERROR: $($File.BaseName) not removed."
            }
        }
    }
}