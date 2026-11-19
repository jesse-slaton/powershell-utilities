<#
.SYNOPSIS
    Copies the current user's Chrome bookmarks file to a backup folder.

.DESCRIPTION
    Copies the Bookmarks file from the Default profile under
    $env:LOCALAPPDATA\Google\Chrome\User Data to <BackupPath>\Chrome-Bookmarks.
    An existing Chrome-Bookmarks file in that folder is not overwritten (Copy-Item is
    called without -Force), so a second run fails with an error. Produces no output.
    Restore-ChromeBookmarks.ps1 copies the file back.

.PARAMETER BackupPath
    Folder that receives the Chrome-Bookmarks copy. The folder must already exist.
    Defaults to C:\DesktopSupportTools.

.EXAMPLE
    .\Backup-ChromeBookmarks.ps1

    Copies the bookmarks to C:\DesktopSupportTools\Chrome-Bookmarks.

.EXAMPLE
    .\Backup-ChromeBookmarks.ps1 -BackupPath 'D:\Backups'

    Copies the bookmarks to D:\Backups\Chrome-Bookmarks.

.NOTES
    Run as the user whose bookmarks are backed up. Only the Default Chrome profile is
    copied. No admin rights needed unless BackupPath requires them.
#>
param(
    # Folder that receives the Chrome-Bookmarks copy (Restore-ChromeBookmarks.ps1 reads it from here).
    [string]$BackupPath = "C:\DesktopSupportTools"
)
$BookmarkPath ="$env:localappdata\Google\Chrome\User Data\Default\Bookmarks"
If ($null -ne $BookmarkPath) {
    Copy-Item -Path $BookmarkPath -Destination "$BackupPath\Chrome-Bookmarks"
}