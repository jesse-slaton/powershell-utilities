# Get the current user's profile folder
$userProfile = $env:USERPROFILE

# Create a backup folder inside the user's profile folder
$backupFolder = Join-Path $userProfile "ChromeBackup"
New-Item -ItemType Directory -Path $backupFolder -Force

# Copy the Chrome profile folder to the backup folder
$chromeProfile = Join-Path $userProfile "AppData\Local\Google\Chrome\User Data\Default"
$backupPath = Join-Path $backupFolder "ChromeProfileBackup"

try {
    Copy-Item -Path $chromeProfile -Destination $backupPath -Recurse -Force -ErrorAction Stop
}
catch {
    Write-Error "Error backing up Chrome profile: $_"
}

# Create a zip file of the backup folder, overwriting any existing zip file
$zipFile = Join-Path $backupFolder "ChromeProfileBackup.zip"
if (Test-Path $zipFile) {
    Remove-Item $zipFile
}
try {
    Compress-Archive -Path $backupPath -DestinationPath $zipFile -Force -ErrorAction Stop
}
catch {
    Write-Error "Error compressing backup folder: $_"
}
