function Get-LidarrTrack {
    [CmdletBinding(DefaultParameterSetName = 'ByAlbumId')]
    param(
        [Parameter(ParameterSetName = 'ByTrackId', Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('Id', 'TrackId')]
        [int[]]$TrackIds,
        
        [Parameter(ParameterSetName = 'ByAlbumId', Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('AlbumId')]
        [int]$AlbumId,
        
        [Parameter(ParameterSetName = 'ByArtistId', Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('ArtistId')]
        [int]$ArtistId,
        
        [Parameter()]
        [switch]$IncludeFileInfo,
        
        [Parameter()]
        [ValidateSet('Title', 'Track', 'Duration', 'Quality')]
        [string]$SortBy
    )
    
    process {
        if ($PSCmdlet.ParameterSetName -eq 'ByTrackId') {
            foreach ($id in $TrackIds) {
                try {
                    $track = Invoke-LidarrApi -Endpoint "track/$id"
                    
                    if ($IncludeFileInfo -and $track.hasFile) {
                        $trackFile = Invoke-LidarrApi -Endpoint "trackfile?trackId=$id"
                        if ($trackFile) {
                            $track | Add-Member -NotePropertyName 'FileInfo' -NotePropertyValue $trackFile -Force
                        }
                    }
                    
                    Write-Output $track
                }
                catch {
                    Write-Error "Failed to retrieve track with ID $id`: $_"
                }
            }
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'ByAlbumId') {
            try {
                $tracks = Invoke-LidarrApi -Endpoint "track?albumId=$AlbumId"
                
                if ($IncludeFileInfo) {
                    # Get track files for tracks that have files
                    $tracksWithFiles = $tracks | Where-Object { $_.hasFile }
                    if ($tracksWithFiles) {
                        $trackFileIds = $tracksWithFiles | ForEach-Object { $_.id }
                        $trackFiles = Invoke-LidarrApi -Endpoint "trackfile"
                        
                        # Match track files to tracks
                        foreach ($track in $tracksWithFiles) {
                            $matchingFile = $trackFiles | Where-Object { $_.trackId -eq $track.id }
                            if ($matchingFile) {
                                $track | Add-Member -NotePropertyName 'FileInfo' -NotePropertyValue $matchingFile -Force
                            }
                        }
                    }
                }
                
                # Apply sorting if specified
                if ($SortBy) {
                    $tracks = ApplyTrackSorting -Tracks $tracks -SortProperty $SortBy
                }
                
                Write-Output $tracks
            }
            catch {
                Write-Error "Failed to retrieve tracks for album ID $AlbumId`: $_"
            }
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'ByArtistId') {
            try {
                $tracks = Invoke-LidarrApi -Endpoint "track?artistId=$ArtistId"
                
                if ($IncludeFileInfo) {
                    # Get track files for tracks that have files
                    $tracksWithFiles = $tracks | Where-Object { $_.hasFile }
                    if ($tracksWithFiles) {
                        $trackFileIds = $tracksWithFiles | ForEach-Object { $_.id }
                        $trackFiles = Invoke-LidarrApi -Endpoint "trackfile"
                        
                        # Match track files to tracks
                        foreach ($track in $tracksWithFiles) {
                            $matchingFile = $trackFiles | Where-Object { $_.trackId -eq $track.id }
                            if ($matchingFile) {
                                $track | Add-Member -NotePropertyName 'FileInfo' -NotePropertyValue $matchingFile -Force
                            }
                        }
                    }
                }
                
                # Apply sorting if specified
                if ($SortBy) {
                    $tracks = ApplyTrackSorting -Tracks $tracks -SortProperty $SortBy
                }
                
                Write-Output $tracks
            }
            catch {
                Write-Error "Failed to retrieve tracks for artist ID $ArtistId`: $_"
            }
        }
    }
}

# Helper function for track sorting
function ApplyTrackSorting {
    param(
        [Parameter(Mandatory)]
        [array]$Tracks,
        
        [Parameter(Mandatory)]
        [string]$SortProperty
    )
    
    switch ($SortProperty.ToLower()) {
        'title' { return $Tracks | Sort-Object -Property title }
        'track' { return $Tracks | Sort-Object -Property trackNumber }
        'duration' { return $Tracks | Sort-Object -Property duration }
        'quality' { return $Tracks | Sort-Object -Property { 
            if ($_.FileInfo.quality.quality.name) { 
                $_.FileInfo.quality.quality.name 
            } else { 
                [string]::Empty 
            }
        }}
        default { return $Tracks }
    }
}