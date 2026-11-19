<#
.SYNOPSIS
    Restores the current user's Chrome bookmarks file from a backup folder.

.DESCRIPTION
    Copies <BackupPath>\Chrome-Bookmarks (written by Backup-ChromeBookmarks.ps1) over the
    Bookmarks file of the Default profile under
    $env:LOCALAPPDATA\Google\Chrome\User Data, replacing it (-Force). Produces no output.

.PARAMETER BackupPath
    Folder that holds the Chrome-Bookmarks copy. Defaults to C:\DesktopSupportTools.

.EXAMPLE
    .\Restore-ChromeBookmarks.ps1

    Restores the bookmarks from C:\DesktopSupportTools\Chrome-Bookmarks.

.EXAMPLE
    .\Restore-ChromeBookmarks.ps1 -BackupPath 'D:\Backups'

    Restores the bookmarks from D:\Backups\Chrome-Bookmarks.

.NOTES
    Run as the user whose bookmarks are restored, with Chrome closed (Chrome rewrites the
    file on exit). Only the Default Chrome profile is restored.
#>
param(
    # Folder that holds the Chrome-Bookmarks copy written by Backup-ChromeBookmarks.ps1 -BackupPath.
    [string]$BackupPath = "C:\DesktopSupportTools"
)
$BookmarkPath ="$env:localappdata\Google\Chrome\User Data\Default\Bookmarks"
If ($null -ne $BookmarkPath) {
    Copy-Item -Path "$BackupPath\Chrome-Bookmarks" -Destination $BookmarkPath -Force
}