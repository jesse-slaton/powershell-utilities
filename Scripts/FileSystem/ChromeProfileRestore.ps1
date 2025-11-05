<#
.SYNOPSIS
    Restores a Google Chrome user profile from a backup archive.

.DESCRIPTION
    This script restores a Chrome profile from a previously created backup ZIP file.
    It checks if a Chrome profile already exists and only restores if the profile
    folder is missing. The backup is extracted from ChromeProfileBackup.zip in the
    ChromeBackup folder. After successful restoration, the backup ZIP file is removed.

.EXAMPLE
    .\ChromeProfileRestore.ps1
    Restores the Chrome profile from %USERPROFILE%\ChromeBackup\ChromeProfileBackup.zip

.EXAMPLE
    .\ChromeProfileRestore.ps1
    Restores Chrome bookmarks, extensions, settings, and history from backup.

.NOTES
    Author: System Administrator
    Purpose: Chrome profile restoration after reinstall or migration
    Requirements: ChromeProfileBackup.zip must exist in %USERPROFILE%\ChromeBackup\
    Behavior: Skips restoration if Chrome profile already exists
    Note: Removes backup ZIP after successful restoration

.LINK
    ChromeProfileBackup.ps1
#>

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
