function Get-LidarrArtist {
    [CmdletBinding(DefaultParameterSetName = 'All')]
    param(
        [Parameter(ParameterSetName = 'ById', Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('Id', 'ArtistId')]
        [int[]]$ArtistIds,
        
        [Parameter(ParameterSetName = 'ByName', Mandatory)]
        [string]$Name,
        
        [Parameter(ParameterSetName = 'ByFilter')]
        [string]$Filter,
        
        [Parameter(ParameterSetName = 'All')]
        [switch]$All,
        
        [Parameter()]
        [ValidateSet('Name', 'Status', 'Type', 'Path', 'Added', 'MonitoredCount', 'TotalCount')]
        [string]$SortBy,
        
        [Parameter()]
        [switch]$Monitored
    )
    
    process {
        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            foreach ($id in $ArtistIds) {
                try {
                    $artist = Invoke-LidarrApi -Endpoint "artist/$id"
                    Write-Output $artist
                }
                catch {
                    Write-Error "Failed to retrieve artist with ID $id`: $_"
                }
            }
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'ByName') {
            $artists = Invoke-LidarrApi -Endpoint "artist"
            $matchingArtists = $artists | Where-Object { $_.artistName -like "*$Name*" }
            if ($matchingArtists) {
                Write-Output $matchingArtists
            } else {
                Write-Warning "No artists found matching name: $Name"
            }
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'ByFilter') {
            $artists = Invoke-LidarrApi -Endpoint "artist"
            $filteredArtists = $artists | Where-Object { $_.artistName -match $Filter }
            if ($filteredArtists) {
                Write-Output $filteredArtists
            } else {
                Write-Warning "No artists found matching filter: $Filter"
            }
        }
        else {
            # Get all artists
            $artists = Invoke-LidarrApi -Endpoint "artist"
            
            # Apply monitored filter if specified
            if ($PSBoundParameters.ContainsKey('Monitored')) {
                $artists = $artists | Where-Object { $_.monitored -eq $Monitored }
            }
            
            # Apply sorting if specified
            if ($SortBy) {
                $sortProperty = $SortBy.ToLower()
                switch ($sortProperty) {
                    'name' { $artists = $artists | Sort-Object -Property artistName }
                    'status' { $artists = $artists | Sort-Object -Property status }
                    'type' { $artists = $artists | Sort-Object -Property artistType }
                    'path' { $artists = $artists | Sort-Object -Property path }
                    'added' { $artists = $artists | Sort-Object -Property added }
                    'monitoredcount' { $artists = $artists | Sort-Object -Property statistics.albumCount }
                    'totalcount' { $artists = $artists | Sort-Object -Property statistics.totalTrackCount }
                }
            }
            
            Write-Output $artists
        }
    }
}