#Requires -Module LidarrPS

<#
.SYNOPSIS
    Unmonitors Lidarr albums listed in a CSV file.
.DESCRIPTION
    This script reads album IDs from a CSV file and unmonitors them in Lidarr.
    The CSV file must have a column with album IDs (named "Id", "AlbumId", etc.)
.PARAMETER LidarrUrl
    URL to the Lidarr server.
.PARAMETER ApiKey
    API key for accessing the Lidarr API.
.PARAMETER CsvPath
    Path to the CSV file containing album IDs to unmonitor.
.PARAMETER DryRun
    If specified, the script will only report what would be unmonitored without making changes.
.EXAMPLE
    .\Unmonitor-AlbumsFromCsv.ps1 -LidarrUrl "http://localhost:8686" -ApiKey "your-api-key" -CsvPath ".\AlbumIDs.csv"
.EXAMPLE
    .\Unmonitor-AlbumsFromCsv.ps1 -LidarrUrl "http://lidarr:8686" -ApiKey "your-api-key" -CsvPath "D:\AlbumList.csv" -DryRun
.NOTES
    Requires the LidarrPS module to be installed.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$LidarrUrl,
    
    [Parameter(Mandatory = $true)]
    [string]$ApiKey,
    
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,
    
    [Parameter()]
    [switch]$DryRun,
    
    [Parameter()]
    [switch]$Confirm
)

# Connect to Lidarr
try {
    Connect-Lidarr -BaseUrl $LidarrUrl -ApiKey $ApiKey
    Write-Host "Successfully connected to Lidarr at $LidarrUrl" -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to Lidarr: $_"
    exit 1
}

# Validate CSV path
if (-not (Test-Path -Path $CsvPath)) {
    Write-Error "CSV file not found: $CsvPath"
    exit 1
}

# Load CSV data
try {
    $csvData = Import-Csv -Path $CsvPath
    
    # Try to identify the album ID column
    $idColumnName = $null
    $csvColumns = $csvData[0].PSObject.Properties.Name
    
    foreach ($column in $csvColumns) {
        if ($column -match "id|album|albumid|album_id" -or $column -eq "Id") {
            $idColumnName = $column
            Write-Verbose "Found album ID column: $idColumnName"
            break
        }
    }
    
    if (-not $idColumnName) {
        Write-Host "Could not find a column with album IDs in the CSV. Available columns:" -ForegroundColor Yellow
        $csvColumns | ForEach-Object { Write-Host "  - $_" }
        Write-Host "Please specify which column to use:" -ForegroundColor Yellow
        $idColumnName = Read-Host "Column name"
        
        if (-not ($csvColumns -contains $idColumnName)) {
            Write-Error "Invalid column name: $idColumnName"
            exit 1
        }
    }
    
    # Extract album IDs
    $albumIds = @($csvData | ForEach-Object { $_.$idColumnName } | 
                 Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                 ForEach-Object { [int]$_ })
    
    Write-Host "Found $($albumIds.Count) album IDs in the CSV file" -ForegroundColor Cyan
}
catch {
    Write-Error "Failed to process CSV file: $_"
    exit 1
}

# Verify we have album IDs
if ($albumIds.Count -eq 0) {
    Write-Error "No valid album IDs found in the CSV file"
    exit 1
}

# Process each album
$processed = 0
$notFound = 0
$alreadyUnmonitored = 0
$unmonitoredCount = 0
$albums = @()

Write-Host "Processing $($albumIds.Count) albums..." -ForegroundColor Cyan

foreach ($id in $albumIds) {
    Write-Progress -Activity "Processing albums" -Status "Album ID: $id" -PercentComplete (($processed / $albumIds.Count) * 100)
    
    try {
        # Get album details
        $album = Get-LidarrAlbum -AlbumIds $id
        
        if (-not $album) {
            Write-Warning "Album ID $id not found in Lidarr"
            $notFound++
            continue
        }
        
        # Get artist info for better output
        $artistId = $album.artistId
        $artist = Get-LidarrArtist -ArtistIds $artistId

        $artistName = if ($artist) { $artist.artistName } else { "Unknown Artist" }
        
        # Only unmonitor if currently monitored
        if (-not $album.monitored) {
            Write-Host "  - $($album.title) by $artistName (Already unmonitored)" -ForegroundColor DarkGray
            $alreadyUnmonitored++
            continue
        }
        
        $albums += @{
            Id = $id
            Title = $album.title
            ArtistName = $artistName
        }
        
        if (-not $DryRun) {
            Set-LidarrMonitoring -AlbumIds $id -Monitored $false -Confirm:$Confirm
            Write-Host "  - $($album.title) by $artistName (Unmonitored)" -ForegroundColor Green
            $unmonitoredCount++
        } else {
            Write-Host "  - $($album.title) by $artistName (Would be unmonitored)" -ForegroundColor DarkYellow
            $unmonitoredCount++
        }
    }
    catch {
        Write-Error "Error processing album ID $id`: $_"
    }
    
    $processed++
}

Write-Progress -Activity "Processing albums" -Completed

# Summary
Write-Host "`nProcessing complete:" -ForegroundColor Cyan
Write-Host "  - Total albums processed: $processed"
Write-Host "  - Albums not found: $notFound"
Write-Host "  - Already unmonitored: $alreadyUnmonitored"

if ($DryRun) {
    Write-Host "  - Would be unmonitored: $unmonitoredCount" -ForegroundColor Yellow
    Write-Host "`nDRY RUN: No changes were made." -ForegroundColor Yellow
} else {
    Write-Host "  - Successfully unmonitored: $unmonitoredCount" -ForegroundColor Green
}