function Get-LidarrAlbum {
    [CmdletBinding(DefaultParameterSetName = 'All')]
    param(
        [Parameter(ParameterSetName = 'ById', Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('Id', 'AlbumId')]
        [int[]]$AlbumIds,
        
        [Parameter(ParameterSetName = 'ByArtistId', Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('ArtistId')]
        [int]$ArtistId,
        
        [Parameter(ParameterSetName = 'ByTitle')]
        [string]$Title,
        
        [Parameter(ParameterSetName = 'ByArtistName')]
        [string]$ArtistName,
        
        [Parameter(ParameterSetName = 'ByFilter')]
        [string]$Filter,
        
        [Parameter(ParameterSetName = 'All')]
        [switch]$All,
        
        [Parameter()]
        [ValidateSet('Title', 'ArtistName', 'ReleaseDate', 'Rating', 'Monitored')]
        [string]$SortBy,
        
        [Parameter()]
        [switch]$Monitored,
        
        [Parameter()]
        [switch]$IncludeAllArtistAlbums
    )
    
    process {
        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            foreach ($id in $AlbumIds) {
                try {
                    $album = Invoke-LidarrApi -Endpoint "album/$id"
                    
                    # Optionally enrich with artist details
                    if ($IncludeAllArtistAlbums) {
                        $artistId = $album.artistId
                        $artist = Invoke-LidarrApi -Endpoint "artist/$artistId"
                        $album | Add-Member -NotePropertyName 'Artist' -NotePropertyValue $artist -Force
                    }
                    
                    Write-Output $album
                }
                catch {
                    Write-Error "Failed to retrieve album with ID $id`: $_"
                }
            }
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'ByArtistId') {
            $albums = Invoke-LidarrApi -Endpoint "album?artistId=$ArtistId"
            
            # Apply monitored filter if specified
            if ($PSBoundParameters.ContainsKey('Monitored')) {
                $albums = $albums | Where-Object { $_.monitored -eq $Monitored }
            }
            
            # Apply sorting if specified
            if ($SortBy) {
                ApplySorting -Albums $albums -SortProperty $SortBy
            }
            
            if ($albums) {
                Write-Output $albums
            } else {
                Write-Warning "No albums found for artist ID: $ArtistId"
            }
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'ByTitle') {
            $allAlbums = Invoke-LidarrApi -Endpoint "album"
            $matchingAlbums = $allAlbums | Where-Object { $_.title -like "*$Title*" }
            
            # Apply monitored filter if specified
            if ($PSBoundParameters.ContainsKey('Monitored')) {
                $matchingAlbums = $matchingAlbums | Where-Object { $_.monitored -eq $Monitored }
            }
            
            # Apply sorting if specified
            if ($SortBy) {
                ApplySorting -Albums $matchingAlbums -SortProperty $SortBy
            }
            
            if ($matchingAlbums) {
                Write-Output $matchingAlbums
            } else {
                Write-Warning "No albums found matching title: $Title"
            }
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'ByArtistName') {
            # First, find artist by name
            $artists = Invoke-LidarrApi -Endpoint "artist"
            $matchingArtists = $artists | Where-Object { $_.artistName -like "*$ArtistName*" }
            
            if (-not $matchingArtists) {
                Write-Warning "No artists found matching name: $ArtistName"
                return
            }
            
            $allMatchingAlbums = @()
            foreach ($artist in $matchingArtists) {
                $albums = Invoke-LidarrApi -Endpoint "album?artistId=$($artist.id)"
                
                # Add artist name to each album for better output
                foreach ($album in $albums) {
                    $album | Add-Member -NotePropertyName 'ArtistName' -NotePropertyValue $artist.artistName -Force
                }
                
                $allMatchingAlbums += $albums
            }
            
            # Apply monitored filter if specified
            if ($PSBoundParameters.ContainsKey('Monitored')) {
                $allMatchingAlbums = $allMatchingAlbums | Where-Object { $_.monitored -eq $Monitored }
            }
            
            # Apply sorting if specified
            if ($SortBy) {
                ApplySorting -Albums $allMatchingAlbums -SortProperty $SortBy
            }
            
            if ($allMatchingAlbums) {
                Write-Output $allMatchingAlbums
            } else {
                Write-Warning "No albums found for artists matching name: $ArtistName"
            }
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'ByFilter') {
            $allAlbums = Invoke-LidarrApi -Endpoint "album"
            $filteredAlbums = $allAlbums | Where-Object { $_.title -match $Filter -or $_.releaseDate -match $Filter }
            
            # Apply monitored filter if specified
            if ($PSBoundParameters.ContainsKey('Monitored')) {
                $filteredAlbums = $filteredAlbums | Where-Object { $_.monitored -eq $Monitored }
            }
            
            # Apply sorting if specified
            if ($SortBy) {
                ApplySorting -Albums $filteredAlbums -SortProperty $SortBy
            }
            
            if ($filteredAlbums) {
                Write-Output $filteredAlbums
            } else {
                Write-Warning "No albums found matching filter: $Filter"
            }
        }
        else {
            # Get all albums
            $allAlbums = Invoke-LidarrApi -Endpoint "album"
            
            # Apply monitored filter if specified
            if ($PSBoundParameters.ContainsKey('Monitored')) {
                $allAlbums = $allAlbums | Where-Object { $_.monitored -eq $Monitored }
            }
            
            # Apply sorting if specified
            if ($SortBy) {
                ApplySorting -Albums $allAlbums -SortProperty $SortBy
            }
            
            Write-Output $allAlbums
        }
    }
}

# Helper function for sorting
function ApplySorting {
    param(
        [Parameter(Mandatory)]
        [ref]$Albums,
        
        [Parameter(Mandatory)]
        [string]$SortProperty
    )
    
    switch ($SortProperty.ToLower()) {
        'title' { $Albums.Value = $Albums.Value | Sort-Object -Property title }
        'artistname' { $Albums.Value = $Albums.Value | Sort-Object -Property { 
            $artistId = $_.artistId
            $artist = Invoke-LidarrApi -Endpoint "artist/$artistId"
            $artist.artistName 
        }}
        'releasedate' { $Albums.Value = $Albums.Value | Sort-Object -Property releaseDate }
        'rating' { $Albums.Value = $Albums.Value | Sort-Object -Property ratings.value -Descending }
        'monitored' { $Albums.Value = $Albums.Value | Sort-Object -Property monitored -Descending }
    }
}