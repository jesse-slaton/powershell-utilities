$BackupPath = "C:\DesktopSupportTools"
$BookmarkPath ="$env:localappdata\Google\Chrome\User Data\Default\Bookmarks"
If ($null -ne $BookmarkPath) {
    Copy-Item -Path "$BackupPath\Chrome-Bookmarks" -Destination $BookmarkPath -Force
}