<#
.SYNOPSIS
    Backs up the Google Chrome user profile to a compressed archive.

.DESCRIPTION
    This script creates a backup of the current user's Chrome profile (Default profile)
    by copying the profile folder and compressing it into a ZIP file. The backup is
    stored in a ChromeBackup folder within the user's profile directory. This is useful
    for preserving Chrome settings, bookmarks, extensions, and history before
    reinstalling or migrating Chrome.

.EXAMPLE
    .\ChromeProfileBackup.ps1
    Creates a backup of the Chrome profile in %USERPROFILE%\ChromeBackup\ChromeProfileBackup.zip

.EXAMPLE
    .\ChromeProfileBackup.ps1
    Backs up Chrome profile including bookmarks, extensions, settings, and history.

.NOTES
    Author: System Administrator
    Purpose: Chrome profile backup for migration or recovery
    Output: Creates ChromeProfileBackup.zip in %USERPROFILE%\ChromeBackup\
    Requirements: Chrome must be closed for complete backup
    Backup Location: %USERPROFILE%\ChromeBackup\ChromeProfileBackup.zip

.LINK
    ChromeProfileRestore.ps1
#>

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
