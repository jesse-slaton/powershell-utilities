<#
.SYNOPSIS
    Creates a sample unmonitored_books_backup.json file for testing a RestoreMonitoring.ps1 script.

.DESCRIPTION
    Writes unmonitored_books_backup.json to the current directory (overwriting any
    existing file). It is a JSON object with a timestamp (the current local time), a
    list of three fake book IDs, a totalCount of 3 and a reason string. Then writes
    the file name, its contents and a reminder about RestoreMonitoring.ps1 to the host.
    RestoreMonitoring.ps1 is not part of this repository.

.EXAMPLE
    .\TestRestoreScript.ps1

    Creates unmonitored_books_backup.json in the current directory and shows it.

.NOTES
    None. No admin rights or modules needed; works in Windows PowerShell 5.1 and
    PowerShell 7.
#>
# Test script to create a sample backup file for testing the restore functionality
# This creates a small backup file so we can test the restore script

$backupData = @{
    timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    unmonitoredBookIds = @(12345, 67890, 11111)  # Sample book IDs for testing
    totalCount = 3
    reason = "Test backup for restore functionality"
}

$backupFile = "unmonitored_books_backup.json"
$backupData | ConvertTo-Json -Depth 3 | Set-Content -Path $backupFile

Write-Host "Test backup file created: $backupFile"
Write-Host "Contents:"
Get-Content $backupFile | Write-Host

Write-Host ""
Write-Host "Now you can test the RestoreMonitoring.ps1 script with this backup file."
Write-Host "Note: The book IDs in this test file are fake, so the restore will likely show warnings."
