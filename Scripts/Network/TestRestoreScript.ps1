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
