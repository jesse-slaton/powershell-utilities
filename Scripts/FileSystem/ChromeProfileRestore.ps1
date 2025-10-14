# Get the current user's profile folder
$userProfile = $env:USERPROFILE

# Check if the Chrome profile folder exists
$chromeProfile = Join-Path $userProfile "AppData\Local\Google\Chrome\User Data\Default"
if (Test-Path $chromeProfile) {
    Write-Output "Chrome profile folder already exists. No restoration needed."
} else {
    # Extract the backup zip file to the Chrome profile folder
    $backupFolder = Join-Path $userProfile "ChromeBackup"
    $zipFile = Join-Path $backupFolder "ChromeProfileBackup.zip"

    if (Test-Path $zipFile) {
        Write-Output "Restoring Chrome profile from backup..."
        Expand-Archive -Path $zipFile -DestinationPath $userProfile -Force
        Write-Output "Chrome profile restored successfully."
        
        # Remove the zip file after restoration
        Remove-Item $zipFile -Force
    } else {
        Write-Output "No backup file found. Chrome profile not restored."
    }
}
