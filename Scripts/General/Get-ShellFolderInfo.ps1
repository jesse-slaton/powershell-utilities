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