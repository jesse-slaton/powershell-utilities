function Find-LidarrQualityAlbums {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('24bit', 'FLAC', 'ALAC', 'MP3', 'AAC')]
        [string[]]$QualityProfile = @('24bit'),
        
        [Parameter()]
        [switch]$CompleteAlbumsOnly,
        
        [Parameter()]
        [switch]$MonitoredOnly,
        
        [Parameter()]
        [switch]$UnmonitoredOnly,
        
        [Parameter()]
        [switch]$UnmonitorAlbums,
        
        [Parameter()]
        [switch]$PassThru
    )
    
    begin {
        # Verify contradicting parameters
        if ($MonitoredOnly -and $UnmonitoredOnly) {
            throw "Cannot specify both -MonitoredOnly and -UnmonitoredOnly."
        }
        
        $qualified = @()
        Write-Verbose "Finding albums matching quality profile: $($QualityProfile -join ', ')"
    }
    
    process {
        try {
            # Get all albums
            $allAlbums = Invoke-LidarrApi -Endpoint "album"
            Write-Verbose "Retrieved $($allAlbums.Count) albums from Lidarr"
            
            # Apply monitored filter if specified
            if ($MonitoredOnly) {
                $allAlbums = $allAlbums | Where-Object { $_.monitored -eq $true }
                Write-Verbose "Filtered to $($allAlbums.Count) monitored albums"
            }
            
            if ($UnmonitoredOnly) {
                $allAlbums = $allAlbums | Where-Object { $_.monitored -eq $false }
                Write-Verbose "Filtered to $($allAlbums.Count) unmonitored albums"
            }
            
            # Get all track files
            $trackFiles = Invoke-LidarrApi -Endpoint "trackfile"
            Write-Verbose "Retrieved $($trackFiles.Count) track files from Lidarr"
            
            # Build lookup table of albums -> track files
            $trackLookup = @{}
            foreach ($track in $trackFiles) {
                $albumId = $track.albumId.ToString()
                
                if (-not $trackLookup.ContainsKey($albumId)) {
                    $trackLookup[$albumId] = @()
                }
                
                # Add this track to the lookup for this album
                $trackLookup[$albumId] += $track
            }
            
            Write-Verbose "Built track lookup table with $($trackLookup.Count) albums"
            
            # Process each album
            foreach ($album in $allAlbums) {
                $id = $album.id.ToString()
                $artistId = $album.artistId.ToString()
                
                # Get artist info for better output
                $artist = Invoke-LidarrApi -Endpoint "artist/$artistId"
                $artistName = if ($artist) { $artist.artistName } else { "Unknown" }
                
                # Skip if no tracks found in lookup
                if (-not $trackLookup.ContainsKey($id)) {
                    Write-Verbose "No tracks found in lookup for album ID: $id ($($album.title) by $artistName)"
                    continue
                }
                
                $albumTracks = $trackLookup[$id]
                $totalTrackCount = $album.statistics.trackCount
                $albumTrackCount = $albumTracks.Count
                
                # Skip incomplete albums if CompleteAlbumsOnly is specified
                if ($CompleteAlbumsOnly -and $albumTrackCount -lt $totalTrackCount) {
                    Write-Verbose "Album $($album.title) by $artistName is incomplete. Has $albumTrackCount of $totalTrackCount tracks."
                    continue
                }
                
                # Check if all tracks match the specified quality
                $allTracksMatchQuality = $true
                foreach ($track in $albumTracks) {
                    $qualityMatches = $false
                    foreach ($quality in $QualityProfile) {
                        # Check for quality match
                        switch ($quality.ToLower()) {
                            '24bit' { 
                                if ($track.quality.quality.name -match '24bit' -or 
                                    $track.mediaInfo.audioBitDepth -eq 24 -or 
                                    $track.mediaInfo.bitDepth -eq 24) {
                                    $qualityMatches = $true
                                }
                            }
                            'flac' { 
                                if ($track.quality.quality.name -match 'FLAC' -or 
                                    $track.mediaInfo.audioFormat -eq 'FLAC') {
                                    $qualityMatches = $true
                                }
                            }
                            'alac' { 
                                if ($track.quality.quality.name -match 'ALAC' -or 
                                    $track.mediaInfo.audioFormat -eq 'ALAC') {
                                    $qualityMatches = $true
                                }
                            }
                            'mp3' { 
                                if ($track.quality.quality.name -match 'MP3' -or 
                                    $track.mediaInfo.audioFormat -eq 'MP3') {
                                    $qualityMatches = $true
                                }
                            }
                            'aac' { 
                                if ($track.quality.quality.name -match 'AAC' -or 
                                    $track.mediaInfo.audioFormat -eq 'AAC') {
                                    $qualityMatches = $true
                                }
                            }
                            default { 
                                # Unknown quality type
                                $qualityMatches = $false
                            }
                        }
                        
                        # Break on first match
                        if ($qualityMatches) {
                            break
                        }
                    }
                    
                    # If any track doesn't match the quality, set flag and break
                    if (-not $qualityMatches) {
                        $allTracksMatchQuality = $false
                        break
                    }
                }
                
                # If all tracks match the quality, add to qualified albums
                if ($allTracksMatchQuality) {
                    Write-Verbose "Album $($album.title) by $artistName qualifies! All $albumTrackCount tracks match quality profile."
                    
                    # Add artist information to album for better output
                    $album | Add-Member -NotePropertyName 'ArtistName' -NotePropertyValue $artistName -Force
                    $album | Add-Member -NotePropertyName 'TrackCount' -NotePropertyValue $albumTrackCount -Force
                    $album | Add-Member -NotePropertyName 'TrackQuality' -NotePropertyValue ($QualityProfile -join ', ') -Force
                    
                    $qualified += $album
                }
            }
            
            # Output summary
            Write-Host "Found $($qualified.Count) albums that meet quality criteria: $($QualityProfile -join ', ')" -ForegroundColor Cyan
            
            # Unmonitor qualified albums if requested
            if ($UnmonitorAlbums -and $qualified.Count -gt 0) {
                Write-Host "Unmonitoring $($qualified.Count) albums..." -ForegroundColor Yellow
                
                foreach ($album in $qualified) {
                    try {
                        # Update monitoring status
                        $album.monitored = $false
                        $albumId = $album.id
                        
                        Invoke-LidarrApi -Endpoint "album/$albumId" -Method "PUT" -Body $album | Out-Null
                        Write-Host "  ✓ Unmonitored: $($album.title) by $($album.ArtistName)" -ForegroundColor Green
                    }
                    catch {
                        Write-Error "Failed to unmonitor album $($album.title) by $($album.ArtistName): $_"
                    }
                }
            }
            
            # Return results if PassThru is specified
            if ($PassThru) {
                Write-Output $qualified
            }
        }
        catch {
            Write-Error "Error finding quality albums: $_"
        }
    }
}