$BackupPath = "C:\DesktopSupportTools"
$BookmarkPath ="$env:localappdata\Google\Chrome\User Data\Default\Bookmarks"
If ($null -ne $BookmarkPath) {
    Copy-Item -Path $BookmarkPath -Destination "$BackupPath\Chrome-Bookmarks"
}