#Requires -Module LidarrPS

<#
.SYNOPSIS
    Finds and unmonitors all complete 24-bit albums in Lidarr.
.DESCRIPTION
    This script identifies all albums in Lidarr that are complete and have all tracks
    in 24-bit audio format, then unmonitors them. This can help with storage management
    by preventing Lidarr from downloading more high-quality audio than necessary.
.PARAMETER LidarrUrl
    URL to the Lidarr server.
.PARAMETER ApiKey
    API key for accessing the Lidarr API.
.PARAMETER DryRun
    If specified, the script will only report what would be unmonitored without making changes.
.EXAMPLE
    .\Unmonitor-24BitAlbums.ps1 -LidarrUrl "http://localhost:8686" -ApiKey "your-api-key"
.EXAMPLE
    .\Unmonitor-24BitAlbums.ps1 -LidarrUrl "http://lidarr:8686" -ApiKey "your-api-key" -DryRun
.NOTES
    Requires the LidarrPS module to be installed.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$LidarrUrl,
    
    [Parameter(Mandatory = $true)]
    [string]$ApiKey,
    
    [Parameter()]
    [switch]$DryRun
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

# Find all 24-bit albums
Write-Host "Finding all complete 24-bit albums..." -ForegroundColor Cyan

$params = @{
    QualityProfile = "24bit"
    CompleteAlbumsOnly = $true
    MonitoredOnly = $true
    PassThru = $true
}

if (-not $DryRun) {
    $params.UnmonitorAlbums = $true
}

$albums = Find-LidarrQualityAlbums @params

# Process results
if ($albums) {
    Write-Host "Found $($albums.Count) complete 24-bit albums:" -ForegroundColor Yellow
    
    foreach ($album in $albums) {
        $artist = if ($album.PSObject.Properties.Name -contains "ArtistName") {
            $album.ArtistName
        } else {
            "Unknown Artist"
        }
        
        if ($DryRun) {
            Write-Host "  - $($album.title) by $artist (would be unmonitored)" -ForegroundColor DarkYellow
        } else {
            Write-Host "  - $($album.title) by $artist (unmonitored)" -ForegroundColor Green
        }
    }
} else {
    Write-Host "No complete 24-bit albums found that are currently monitored." -ForegroundColor Cyan
}

# Summary
if ($DryRun) {
    Write-Host "`nDRY RUN: No changes were made." -ForegroundColor Yellow
} elseif ($albums) {
    Write-Host "`nSuccessfully unmonitored $($albums.Count) complete 24-bit albums." -ForegroundColor Green
}