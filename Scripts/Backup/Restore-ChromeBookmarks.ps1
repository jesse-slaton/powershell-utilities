param(
    # Folder that holds the Chrome-Bookmarks copy written by Backup-ChromeBookmarks.ps1 -BackupPath.
    [string]$BackupPath = "C:\DesktopSupportTools"
)
$BookmarkPath ="$env:localappdata\Google\Chrome\User Data\Default\Bookmarks"
If ($null -ne $BookmarkPath) {
    Copy-Item -Path "$BackupPath\Chrome-Bookmarks" -Destination $BookmarkPath -Force
}