param(
    # Folder that receives the Chrome-Bookmarks copy (Restore-ChromeBookmarks.ps1 reads it from here).
    [string]$BackupPath = "C:\DesktopSupportTools"
)
$BookmarkPath ="$env:localappdata\Google\Chrome\User Data\Default\Bookmarks"
If ($null -ne $BookmarkPath) {
    Copy-Item -Path $BookmarkPath -Destination "$BackupPath\Chrome-Bookmarks"
}