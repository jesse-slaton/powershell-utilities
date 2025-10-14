function Set-LidarrMonitoring {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Album')]
    param(
        [Parameter(ParameterSetName = 'Artist', Mandatory, ValueFromPipeline)]
        [Parameter(ParameterSetName = 'Album', ValueFromPipeline)]
        [PSObject]$InputObject,
        
        [Parameter(ParameterSetName = 'Artist')]
        [Alias('ArtistId')]
        [int[]]$ArtistIds,
        
        [Parameter(ParameterSetName = 'Album', Mandatory)]
        [Alias('AlbumId')]
        [int[]]$AlbumIds,
        
        [Parameter()]
        [bool]$Monitored,
        
        [Parameter()]
        [switch]$PassThru
    )
    
    begin {
        # Initialize collections
        $processedArtistIds = @()
        $processedAlbumIds = @()
        $results = @()
    }
    
    process {
        # Process input from pipeline
        if ($InputObject) {
            if ($InputObject.PSObject.Properties.Name -contains 'artistId' -and $InputObject.PSObject.Properties.Name -contains 'title') {
                # This looks like an album object
                $AlbumIds += $InputObject.id
            }
            elseif ($InputObject.PSObject.Properties.Name -contains 'artistType') {
                # This looks like an artist object
                $ArtistIds += $InputObject.id
            }
            else {
                Write-Warning "Unrecognized object type passed via pipeline. The object must be an artist or album."
                return
            }
        }
        
        # Process artists
        if ($PSCmdlet.ParameterSetName -eq 'Artist' -or $ArtistIds) {
            foreach ($id in $ArtistIds) {
                # Skip if already processed
                if ($processedArtistIds -contains $id) { continue }
                $processedArtistIds += $id
                
                try {
                    # Get artist
                    $artist = Invoke-LidarrApi -Endpoint "artist/$id"
                    
                    if ($null -eq $artist) {
                        Write-Warning "Artist with ID $id not found."
                        continue
                    }
                    
                    # Update monitoring status
                    $originalStatus = $artist.monitored
                    $artist.monitored = $Monitored
                    
                    $actionDescription = if ($Monitored) { "enable" } else { "disable" }
                    if ($PSCmdlet.ShouldProcess("Artist: $($artist.artistName)", "$($actionDescription) monitoring")) {
                        Invoke-LidarrApi -Endpoint "artist/$id" -Method "PUT" -Body $artist | Out-Null
                        Write-Verbose "Artist $($artist.artistName) monitoring set to: $Monitored (was: $originalStatus)"
                        
                        if ($PassThru) {
                            $results += $artist
                        }
                    }
                }
                catch {
                    Write-Error "Failed to update monitoring for artist ID $id`: $_"
                }
            }
        }
        
        # Process albums
        if ($PSCmdlet.ParameterSetName -eq 'Album' -or $AlbumIds) {
            foreach ($id in $AlbumIds) {
                # Skip if already processed
                if ($processedAlbumIds -contains $id) { continue }
                $processedAlbumIds += $id
                
                try {
                    # Get album
                    $album = Invoke-LidarrApi -Endpoint "album/$id"
                    
                    if ($null -eq $album) {
                        Write-Warning "Album with ID $id not found."
                        continue
                    }
                    
                    # Get artist name for better output
                    $artist = Invoke-LidarrApi -Endpoint "artist/$($album.artistId)"
                    $artistName = if ($artist) { $artist.artistName } else { "Unknown Artist" }
                    
                    # Update monitoring status
                    $originalStatus = $album.monitored
                    $album.monitored = $Monitored
                    
                    $actionDescription = if ($Monitored) { "enable" } else { "disable" }
                    if ($PSCmdlet.ShouldProcess("Album: $($album.title) by $artistName", "$($actionDescription) monitoring")) {
                        Invoke-LidarrApi -Endpoint "album/$id" -Method "PUT" -Body $album | Out-Null
                        Write-Verbose "Album $($album.title) by $artistName monitoring set to: $Monitored (was: $originalStatus)"
                        
                        if ($PassThru) {
                            $results += $album
                        }
                    }
                }
                catch {
                    Write-Error "Failed to update monitoring for album ID $id`: $_"
                }
            }
        }
    }
    
    end {
        if ($PassThru -and $results) {
            Write-Output $results
        }
    }
}