<#
.SYNOPSIS
This script restores monitoring for books that were previously unmonitored by the UnmonitorReadarr script.

.DESCRIPTION
The script reads from a backup file that contains the book IDs that were unmonitored by the UnmonitorReadarr script.
It then restores monitoring for only those specific books, not all unmonitored books in Readarr.
This ensures you don't accidentally re-monitor books that were intentionally unmonitored for other reasons.

.PARAMETER BackupFile
Path to the backup file containing the book IDs that were unmonitored. Defaults to "unmonitored_books_backup.json"

.PARAMETER Force
Skip confirmation prompt and proceed with restoration

.INPUTS
None. You cannot pipe objects to this script.

.OUTPUTS
None. This script does not output any objects.

.NOTES
    Version:        1.0.0
    Author:         Jesse Slaton
    Creation Date:  2024-01-XX
    Purpose/Change: Improved restore functionality with backup file support

#>

param(
    [string]$BackupFile = "unmonitored_books_backup.json",
    [switch]$Force
)

# Define Readarr API variables
$ReadarrApiKey = "<READARR_API_KEY>"
$ReadarrBaseUrl = "http://192.168.1.10:8787/readarr"

# Initialize log file
$logFile = "readarr_restore_log.txt"
Set-Content -Path $logFile -Value "$(Get-Date): Starting restore monitoring process"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp - $Message"
    Write-Host $logEntry
    Add-Content -Path $logFile -Value $logEntry
}

try {
    # Check if backup file exists
    if (-not (Test-Path $BackupFile)) {
        Write-Error "Backup file '$BackupFile' not found. Please ensure you have a backup from the UnmonitorReadarr script."
        Write-Log "ERROR: Backup file '$BackupFile' not found"
        exit 1
    }

    # Load the backup file
    Write-Log "Loading backup file: $BackupFile"
    $backupData = Get-Content -Path $BackupFile -Raw | ConvertFrom-Json
    
    if (-not $backupData.unmonitoredBookIds -or $backupData.unmonitoredBookIds.Count -eq 0) {
        Write-Warning "No book IDs found in backup file or backup file is empty."
        Write-Log "WARNING: No book IDs found in backup file"
        exit 0
    }

    $bookIdsToRestore = $backupData.unmonitoredBookIds
    Write-Log "Found $($bookIdsToRestore.Count) book IDs in backup file"
    Write-Host "Backup created on: $($backupData.timestamp)"
    Write-Host "Books to restore: $($bookIdsToRestore.Count)"

    # Show confirmation unless Force is used
    if (-not $Force) {
        $confirmation = Read-Host "Do you want to restore monitoring for $($bookIdsToRestore.Count) books? (y/N)"
        if ($confirmation -ne 'y' -and $confirmation -ne 'Y') {
            Write-Log "User cancelled restoration"
            Write-Host "Restoration cancelled by user."
            exit 0
        }
    }

    # Verify books still exist in Readarr and are currently unmonitored
    Write-Log "Verifying books in Readarr..."
    $validBookIds = @()
    $batchSize = 50  # Process in smaller batches to avoid overwhelming the API

    for ($i = 0; $i -lt $bookIdsToRestore.Count; $i += $batchSize) {
        $batch = $bookIdsToRestore[$i..[math]::Min($i + $batchSize - 1, $bookIdsToRestore.Count - 1)]
        Write-Progress -Activity "Verifying Books" -Status "Batch $([math]::Floor($i / $batchSize) + 1) of $([math]::Ceiling($bookIdsToRestore.Count / $batchSize))" -PercentComplete (($i / $bookIdsToRestore.Count) * 100)
        
        foreach ($bookId in $batch) {
            try {
                $bookUrl = "$ReadarrBaseUrl/api/v1/book/$bookId" + "?apikey=$ReadarrApiKey"
                $book = Invoke-RestMethod -Uri $bookUrl -Method Get -ErrorAction Stop
                
                if ($book.monitored -eq $false) {
                    $validBookIds += $bookId
                    Write-Log "Book ID $bookId ('$($book.title)') is valid and unmonitored"
                } else {
                    Write-Log "Book ID $bookId ('$($book.title)') is already monitored - skipping"
                }
            }
            catch {
                Write-Log "WARNING: Book ID $bookId not found or error accessing: $($_.Exception.Message)"
            }
        }
    }
    Write-Progress -Activity "Verifying Books" -Completed

    if ($validBookIds.Count -eq 0) {
        Write-Warning "No valid unmonitored books found to restore."
        Write-Log "No valid books to restore"
        exit 0
    }

    Write-Log "Found $($validBookIds.Count) valid books to restore monitoring"
    
    # Restore monitoring for valid books
    Write-Log "Starting restoration process..."
    $url = "$ReadarrBaseUrl/api/v1/book/monitor?apikey=$ReadarrApiKey"
    $body = @{
        "bookIds"   = @($validBookIds)
        "monitored" = $true
    }
    
    $jsonBody = $body | ConvertTo-Json -Depth 3
    Write-Log "Sending restore request to Readarr API"
    
    $result = Invoke-RestMethod -Uri $url -Method Put -Body $jsonBody -ContentType "application/json"
    
    Write-Log "Successfully restored monitoring for $($validBookIds.Count) books"
    Write-Host ""
    Write-Host "Restoration Summary:" -ForegroundColor Green
    Write-Host "  - Books in backup: $($bookIdsToRestore.Count)"
    Write-Host "  - Valid books found: $($validBookIds.Count)" 
    Write-Host "  - Books restored: $($validBookIds.Count)"
    Write-Host "  - Already monitored: $($bookIdsToRestore.Count - $validBookIds.Count)"
    Write-Host ""
    
    # Display restored book titles
    if ($result -and $result.title) {
        Write-Host "Restored books:" -ForegroundColor Cyan
        $result.title | Sort-Object | ForEach-Object { Write-Host "  - $_" }
    }

    # Create a restore log
    $restoreLogData = @{
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        restoredBookIds = $validBookIds
        restoredCount = $validBookIds.Count
        backupFile = $BackupFile
    }
    $restoreLogPath = "restore_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $restoreLogData | ConvertTo-Json -Depth 3 | Set-Content -Path $restoreLogPath
    Write-Log "Restore log saved to: $restoreLogPath"

}
catch {
    $errorMessage = "Error during restoration: $($_.Exception.Message)"
    Write-Error $errorMessage
    Write-Log "ERROR: $errorMessage"
    exit 1
}
