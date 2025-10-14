# Function to log messages with date/time and type (Info or Error)
function Log-Message {
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Error')]
        [string]$Type = 'Info'
    )

    $logPath = "C:\Contoso\Logs\BackupChromeBookmarks.log"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$Type] [$env:USERNAME] $Message"

    # Ensure the log directory exists
    if (-not (Test-Path -Path (Split-Path -Path $logPath -Parent))) {
        New-Item -ItemType Directory -Path (Split-Path -Path $logPath -Parent) | Out-Null
    }

    # Write the log message to the log file
    Add-Content -Path $logPath -Value $logMessage
}

# Define the backup destination and start logging
$backupPath = "H:\Backups\ChromeBookmarks"
Log-Message -Message "Backup process started." -Type Info

# Initialize timeout settings
$timeout = New-TimeSpan -Minutes 5
$stopwatch = [diagnostics.stopwatch]::StartNew()

while ($true) {
    if (Test-Path H:) {
        if (-not (Test-Path $backupPath)) {
            New-Item -Path $backupPath -ItemType Directory | Out-Null
            Log-Message -Message "Created backup directory at $backupPath." -Type Info
        }

        # Define the path to the Chrome bookmarks file.
        $chromeBookmarksPath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Bookmarks"

        if (Test-Path $chromeBookmarksPath) {
            Copy-Item -Path $chromeBookmarksPath -Destination $backupPath -Force
            Log-Message -Message "Chrome bookmarks successfully backed up." -Type Info
        } else {
            Log-Message -Message "Chrome bookmarks file does not exist." -Type Error
        }
        break # Exit loop on success
    } else {
        if ($stopwatch.Elapsed -ge $timeout) {
            Log-Message -Message "H: drive is not accessible. Exiting after 5 minutes." -Type Error
            break # Exit loop on timeout
        } else {
            Log-Message -Message "H: drive is not accessible. Retrying in 60 seconds." -Type Info
            Start-Sleep -Seconds 60
        }
    }
}
