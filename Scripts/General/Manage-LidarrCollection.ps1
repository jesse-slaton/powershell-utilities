#Requires -Module LidarrPS

<#
.SYNOPSIS
    Advanced Lidarr collection management script.
.DESCRIPTION
    This script demonstrates advanced usage of the LidarrPS module to manage collections,
    showcasing pipeline usage, filtering, and batch operations.
.PARAMETER LidarrUrl
    URL to the Lidarr server.
.PARAMETER ApiKey
    API key for accessing the Lidarr API.
.PARAMETER ArtistName
    Optional artist name filter to limit operations.
.PARAMETER Action
    Action to perform: List, Unmonitor24Bit, MonitorIncomplete, or QualityReport.
.PARAMETER DryRun
    If specified, no changes will be made to Lidarr (for actions that modify data).
.EXAMPLE
    .\Manage-LidarrCollection.ps1 -LidarrUrl "http://localhost:8686" -ApiKey "your-api-key" -Action QualityReport
    Generates a report of all albums by quality.
.EXAMPLE
    .\Manage-LidarrCollection.ps1 -LidarrUrl "http://localhost:8686" -ApiKey "your-api-key" -Action Unmonitor24Bit -ArtistName "Adele"
    Unmonitors all 24-bit albums by Adele.
.NOTES
    Requires the LidarrPS module to be installed.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$LidarrUrl,
    
    [Parameter(Mandatory = $true)]
    [string]$ApiKey,
    
    [Parameter()]
    [string]$ArtistName,
    
    [Parameter(Mandatory = $true)]
    [ValidateSet('List', 'Unmonitor24Bit', 'MonitorIncomplete', 'QualityReport')]
    [string]$Action,
    
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

# Helper function to format storage size
function Format-StorageSize {
    param([long]$SizeBytes)
    
    if ($SizeBytes -ge 1TB) {
        return "{0:N2} TB" -f ($SizeBytes / 1TB)
    }
    elseif ($SizeBytes -ge 1GB) {
        return "{0:N2} GB" -f ($SizeBytes / 1GB)
    }
    elseif ($SizeBytes -ge 1MB) {
        return "{0:N2} MB" -f ($SizeBytes / 1MB)
    }
    elseif ($SizeBytes -ge 1KB) {
        return "{0:N2} KB" -f ($SizeBytes / 1KB)
    }
    else {
        return "$SizeBytes bytes"
    }
}

# Helper function to get all relevant artists
function Get-RelevantArtists {
    if ($ArtistName) {
        Get-LidarrArtist -Name $ArtistName
    }
    else {
        Get-LidarrArtist
    }
}

# Perform the requested action
switch ($Action) {
    'List' {
        $artists = Get-RelevantArtists
        
        if (-not $artists) {
            Write-Warning "No artists found matching filter"
            exit 0
        }
        
        $totalAlbums = 0
        $totalMonitored = 0
        $totalUnmonitored = 0
        
        foreach ($artist in $artists) {
            $albums = Get-LidarrAlbum -ArtistId $artist.id
            
            $monitored = ($albums | Where-Object { $_.monitored }).Count
            $unmonitored = ($albums | Where-Object { -not $_.monitored }).Count
            
            Write-Host "`n$($artist.artistName)" -ForegroundColor Cyan
            Write-Host "  Total Albums: $($albums.Count)"
            Write-Host "  Monitored: $monitored"
            Write-Host "  Unmonitored: $unmonitored"
            
            if ($albums.Count -gt 0) {
                Write-Host "  Albums:" -ForegroundColor DarkCyan
                foreach ($album in $albums) {
                    $status = if ($album.monitored) { "✓" } else { "✗" }
                    $color = if ($album.monitored) { "Green" } else { "DarkGray" }
                    Write-Host "    [$status] $($album.title) ($($album.releaseDate.Substring(0, 4)))" -ForegroundColor $color
                }
            }
            
            $totalAlbums += $albums.Count
            $totalMonitored += $monitored
            $totalUnmonitored += $unmonitored
        }
        
        Write-Host "`n======= SUMMARY =======" -ForegroundColor Yellow
        Write-Host "Artists: $($artists.Count)"
        Write-Host "Total Albums: $totalAlbums"
        Write-Host "Total Monitored: $totalMonitored"
        Write-Host "Total Unmonitored: $totalUnmonitored"
    }
    
    'Unmonitor24Bit' {
        Write-Host "Finding and unmonitoring 24-bit albums..." -ForegroundColor Cyan
        
        $artists = Get-RelevantArtists
        
        if (-not $artists) {
            Write-Warning "No artists found matching filter"
            exit 0
        }
        
        $totalUnmonitored = 0
        
        foreach ($artist in $artists) {
            Write-Host "`nProcessing artist: $($artist.artistName)" -ForegroundColor Cyan
            
            # Get all albums for this artist
            $albums = Get-LidarrAlbum -ArtistId $artist.id -Monitored:$true
            
            if (-not $albums) {
                Write-Host "  No monitored albums found for this artist" -ForegroundColor DarkGray
                continue
            }
            
            $artistTotal = 0
            
            foreach ($album in $albums) {
                # Get tracks with file information
                $tracks = Get-LidarrTrack -AlbumId $album.id -IncludeFileInfo
                $trackFiles = $tracks | Where-Object { $_.hasFile -and $_.FileInfo }
                
                if (-not $trackFiles -or $trackFiles.Count -eq 0) {
                    continue
                }
                
                # Check if all tracks are 24-bit
                $all24Bit = $true
                foreach ($track in $trackFiles) {
                    $is24Bit = ($track.FileInfo.quality.quality.name -match '24bit') -or 
                               ($track.FileInfo.mediaInfo.audioBitDepth -eq 24) -or 
                               ($track.FileInfo.mediaInfo.bitDepth -eq 24)
                    
                    if (-not $is24Bit) {
                        $all24Bit = $false
                        break
                    }
                }
                
                # If all tracks are 24-bit and the album is complete
                if ($all24Bit -and $album.statistics.trackCount -eq $album.statistics.trackFileCount) {
                    if (-not $DryRun) {
                        Set-LidarrMonitoring -AlbumIds $album.id -Monitored $false -Confirm:$false
                        Write-Host "  ✔ Unmonitored: $($album.title)" -ForegroundColor Green
                    } else {
                        Write-Host "  ✓ Would unmonitor: $($album.title)" -ForegroundColor DarkYellow
                    }
                    $artistTotal++
                    $totalUnmonitored++
                }
            }
            
            Write-Host "  Found $artistTotal 24-bit complete albums for $($artist.artistName)" -ForegroundColor Cyan
        }
        
        Write-Host "`n======= SUMMARY =======" -ForegroundColor Yellow
        if ($DryRun) {
            Write-Host "Would unmonitor $totalUnmonitored complete 24-bit albums" -ForegroundColor Yellow
            Write-Host "DRY RUN: No changes were made." -ForegroundColor Yellow
        } else {
            Write-Host "Successfully unmonitored $totalUnmonitored complete 24-bit albums" -ForegroundColor Green
        }
    }
    
    'MonitorIncomplete' {
        Write-Host "Finding and monitoring incomplete albums..." -ForegroundColor Cyan
        
        $artists = Get-RelevantArtists
        
        if (-not $artists) {
            Write-Warning "No artists found matching filter"
            exit 0
        }
        
        $totalMonitored = 0
        
        foreach ($artist in $artists) {
            Write-Host "`nProcessing artist: $($artist.artistName)" -ForegroundColor Cyan
            
            # Get all unmonitored albums for this artist
            $albums = Get-LidarrAlbum -ArtistId $artist.id -Monitored:$false
            
            if (-not $albums) {
                Write-Host "  No unmonitored albums found for this artist" -ForegroundColor DarkGray
                continue
            }
            
            $artistTotal = 0
            
            foreach ($album in $albums) {
                # Check if album has some but not all tracks
                $hasFiles = $album.statistics.trackFileCount -gt 0
                $isIncomplete = $album.statistics.trackFileCount -lt $album.statistics.trackCount
                
                if ($hasFiles -and $isIncomplete) {
                    $percentComplete = [math]::Round(($album.statistics.trackFileCount / $album.statistics.trackCount) * 100)
                    
                    if (-not $DryRun) {
                        Set-LidarrMonitoring -AlbumIds $album.id -Monitored $true -Confirm:$false
                        Write-Host "  ✔ Monitored: $($album.title) ($percentComplete% complete - $($album.statistics.trackFileCount)/$($album.statistics.trackCount) tracks)" -ForegroundColor Green
                    } else {
                        Write-Host "  ✓ Would monitor: $($album.title) ($percentComplete% complete - $($album.statistics.trackFileCount)/$($album.statistics.trackCount) tracks)" -ForegroundColor DarkYellow
                    }
                    $artistTotal++
                    $totalMonitored++
                }
            }
            
            Write-Host "  Found $artistTotal incomplete albums for $($artist.artistName)" -ForegroundColor Cyan
        }
        
        Write-Host "`n======= SUMMARY =======" -ForegroundColor Yellow
        if ($DryRun) {
            Write-Host "Would monitor $totalMonitored incomplete albums" -ForegroundColor Yellow
            Write-Host "DRY RUN: No changes were made." -ForegroundColor Yellow
        } else {
            Write-Host "Successfully monitored $totalMonitored incomplete albums" -ForegroundColor Green
        }
    }
    
    'QualityReport' {
        Write-Host "Generating quality report for all albums..." -ForegroundColor Cyan
        
        $artists = Get-RelevantArtists
        
        if (-not $artists) {
            Write-Warning "No artists found matching filter"
            exit 0
        }
        
        # Initialize counters
        $qualityStats = @{
            '24bit FLAC' = @{ Count = 0; SizeBytes = 0 }
            '16bit FLAC' = @{ Count = 0; SizeBytes = 0 }
            'FLAC' = @{ Count = 0; SizeBytes = 0 }
            'MP3' = @{ Count = 0; SizeBytes = 0 }
            'AAC' = @{ Count = 0; SizeBytes = 0 }
            'Other' = @{ Count = 0; SizeBytes = 0 }
            'Total' = @{ Count = 0; SizeBytes = 0 }
        }
        
        # Track albums by quality
        $albumsByQuality = @{
            '24bit FLAC' = @()
            '16bit FLAC' = @()
            'FLAC' = @()
            'MP3' = @()
            'AAC' = @()
            'Other' = @()
        }
        
        foreach ($artist in $artists) {
            Write-Host "`nProcessing artist: $($artist.artistName)" -ForegroundColor Cyan
            
            # Get all albums for this artist
            $albums = Get-LidarrAlbum -ArtistId $artist.id
            
            if (-not $albums) {
                Write-Host "  No albums found for this artist" -ForegroundColor DarkGray
                continue
            }
            
            foreach ($album in $albums) {
                $tracks = Get-LidarrTrack -AlbumId $album.id -IncludeFileInfo
                $trackFiles = $tracks | Where-Object { $_.hasFile -and $_.FileInfo }
                
                if (-not $trackFiles -or $trackFiles.Count -eq 0) {
                    continue
                }
                
                # Determine album quality based on majority of tracks
                $qualityCounts = @{
                    '24bit FLAC' = 0
                    '16bit FLAC' = 0
                    'FLAC' = 0
                    'MP3' = 0
                    'AAC' = 0
                    'Other' = 0
                }
                
                $albumSize = 0
                
                foreach ($track in $trackFiles) {
                    $fileInfo = $track.FileInfo
                    $albumSize += $fileInfo.size
                    
                    if ($fileInfo.quality.quality.name -match '24bit' -or $fileInfo.mediaInfo.audioBitDepth -eq 24) {
                        $qualityCounts['24bit FLAC']++
                    }
                    elseif ($fileInfo.quality.quality.name -match 'FLAC' -and ($fileInfo.mediaInfo.audioBitDepth -eq 16 -or $fileInfo.mediaInfo.audioBitDepth -eq $null)) {
                        $qualityCounts['16bit FLAC']++
                    }
                    elseif ($fileInfo.quality.quality.name -match 'FLAC') {
                        $qualityCounts['FLAC']++
                    }
                    elseif ($fileInfo.quality.quality.name -match 'MP3') {
                        $qualityCounts['MP3']++
                    }
                    elseif ($fileInfo.quality.quality.name -match 'AAC') {
                        $qualityCounts['AAC']++
                    }
                    else {
                        $qualityCounts['Other']++
                    }
                }
                
                # Determine majority quality
                $maxQuality = $qualityCounts.GetEnumerator() | 
                              Sort-Object Value -Descending | 
                              Select-Object -First 1 -ExpandProperty Key
                
                # Add to quality stats
                $qualityStats[$maxQuality].Count++
                $qualityStats[$maxQuality].SizeBytes += $albumSize
                $qualityStats['Total'].Count++
                $qualityStats['Total'].SizeBytes += $albumSize
                
                # Add album to quality list
                $albumInfo = [PSCustomObject]@{
                    Title = $album.title
                    Artist = $artist.artistName
                    TrackCount = $trackFiles.Count
                    Size = $albumSize
                    SizeFormatted = Format-StorageSize -SizeBytes $albumSize
                    Quality = $maxQuality
                    Year = if ($album.releaseDate) { $album.releaseDate.Substring(0, 4) } else { "Unknown" }
                    Monitored = $album.monitored
                }
                
                $albumsByQuality[$maxQuality] += $albumInfo
            }
        }
        
        # Display report
        Write-Host "`n======= QUALITY REPORT =======" -ForegroundColor Yellow
        
        # Overall stats
        $totalAlbums = $qualityStats['Total'].Count
        if ($totalAlbums -eq 0) {
            Write-Host "No albums with files found" -ForegroundColor Yellow
            return
        }
        
        $totalSize = Format-StorageSize -SizeBytes $qualityStats['Total'].SizeBytes
        
        Write-Host "Total Albums: $totalAlbums"
        Write-Host "Total Size: $totalSize"
        
        # Quality breakdown
        Write-Host "`nQuality Breakdown:" -ForegroundColor Cyan
        
        foreach ($quality in @('24bit FLAC', '16bit FLAC', 'FLAC', 'MP3', 'AAC', 'Other')) {
            $count = $qualityStats[$quality].Count
            if ($count -gt 0) {
                $percentage = [math]::Round(($count / $totalAlbums) * 100, 1)
                $size = Format-StorageSize -SizeBytes $qualityStats[$quality].SizeBytes
                Write-Host "$quality`: $count albums ($percentage%) - $size"
            }
        }
        
        # Top albums by size
        Write-Host "`nTop 10 Largest Albums:" -ForegroundColor Cyan
        $allAlbums = @()
        foreach ($quality in $albumsByQuality.Keys) {
            $allAlbums += $albumsByQuality[$quality]
        }
        
        $allAlbums | 
            Sort-Object -Property Size -Descending | 
            Select-Object -First 10 | 
            ForEach-Object {
                $monStatus = if ($_.Monitored) { "[✓]" } else { "[✗]" }
                $color = if ($_.Monitored) { "Green" } else { "DarkGray" }
                Write-Host "$monStatus $($_.Title) by $($_.Artist) ($($_.Year)) - Quality: $($_.Quality) - Size: $($_.SizeFormatted)" -ForegroundColor $color
            }
            
        # Detailed quality reports
        foreach ($quality in @('24bit FLAC', '16bit FLAC', 'FLAC', 'MP3', 'AAC', 'Other')) {
            $albums = $albumsByQuality[$quality]
            if ($albums.Count -gt 0) {
                Write-Host "`n$quality Albums ($($albums.Count)):" -ForegroundColor Cyan
                $albums | 
                    Sort-Object -Property Size -Descending | 
                    Select-Object -First 5 | 
                    ForEach-Object {
                        $monStatus = if ($_.Monitored) { "[✓]" } else { "[✗]" }
                        $color = if ($_.Monitored) { "Green" } else { "DarkGray" }
                        Write-Host "$monStatus $($_.Title) by $($_.Artist) ($($_.Year)) - $($_.SizeFormatted)" -ForegroundColor $color
                    }
                
                if ($albums.Count -gt 5) {
                    Write-Host "  ...and $($albums.Count - 5) more albums" -ForegroundColor DarkGray
                }
            }
        }
        
        # Monitored status by quality
        Write-Host "`nMonitoring Status by Quality:" -ForegroundColor Yellow
        foreach ($quality in @('24bit FLAC', '16bit FLAC', 'FLAC', 'MP3', 'AAC', 'Other')) {
            $albums = $albumsByQuality[$quality]
            if ($albums.Count -gt 0) {
                $monitored = ($albums | Where-Object { $_.Monitored }).Count
                $unmonitored = $albums.Count - $monitored
                $monitoredPercentage = [math]::Round(($monitored / $albums.Count) * 100, 1)
                
                Write-Host "$quality`: $monitored monitored ($monitoredPercentage%), $unmonitored unmonitored"
            }
        }
    }
}