BeforeAll {
    # Import the module
    $ModulePath = "$PSScriptRoot\.."
    Import-Module $ModulePath -Force
}

Describe "Get-LidarrArtist" {
    BeforeEach {
        # Mock artist data
        $mockArtists = @(
            @{
                id = 1
                artistName = "Adele"
                status = "continuing"
                path = "/music/Adele"
                qualityProfileId = 1
                metadataProfileId = 1
                monitored = $true
                albumFolder = $true
                added = "2022-01-01T12:00:00Z"
                artistType = "Person"
                cleanName = "adele"
                sortName = "adele"
                statistics = @{
                    albumCount = 5
                    trackCount = 50
                    totalTrackCount = 55
                    sizeOnDisk = 2048576000
                }
            },
            @{
                id = 2
                artistName = "The Beatles"
                status = "ended"
                path = "/music/The Beatles"
                qualityProfileId = 1
                metadataProfileId = 1
                monitored = $true
                albumFolder = $true
                added = "2022-01-02T12:00:00Z"
                artistType = "Group"
                cleanName = "beatles the"
                sortName = "beatles the"
                statistics = @{
                    albumCount = 15
                    trackCount = 200
                    totalTrackCount = 213
                    sizeOnDisk = 5242880000
                }
            },
            @{
                id = 3
                artistName = "Pink Floyd"
                status = "ended"
                path = "/music/Pink Floyd"
                qualityProfileId = 1
                metadataProfileId = 1
                monitored = $false
                albumFolder = $true
                added = "2022-01-03T12:00:00Z"
                artistType = "Group"
                cleanName = "pink floyd"
                sortName = "pink floyd"
                statistics = @{
                    albumCount = 10
                    trackCount = 120
                    totalTrackCount = 150
                    sizeOnDisk = 3221225472
                }
            }
        )
        
        # Setup connection and mock API calls
        $Script:LidarrConnection = @{
            BaseUrl = "http://localhost:8686"
            ApiKey = "testapikey123"
            WebSession = $null
        }
        
        # Mock all artists
        Mock -CommandName Invoke-LidarrApi -ModuleName LidarrPS -ParameterFilter {
            $Endpoint -eq "artist"
        } -MockWith {
            return $mockArtists
        }
        
        # Mock specific artist
        Mock -CommandName Invoke-LidarrApi -ModuleName LidarrPS -ParameterFilter {
            $Endpoint -match "artist/\d+"
        } -MockWith {
            $id = [int]($Endpoint -replace "artist/", "")
            return $mockArtists | Where-Object { $_.id -eq $id }
        }
    }
    
    It "Should get all artists" {
        $result = Get-LidarrArtist
        
        $result | Should -HaveCount 3
        $result[0].artistName | Should -Be "Adele"
    }
    
    It "Should get artist by ID" {
        $result = Get-LidarrArtist -ArtistIds 2
        
        $result | Should -HaveCount 1
        $result.artistName | Should -Be "The Beatles"
    }
    
    It "Should get artist by name" {
        $result = Get-LidarrArtist -Name "Pink"
        
        $result | Should -HaveCount 1
        $result.artistName | Should -Be "Pink Floyd"
    }
    
    It "Should get artist by regex filter" {
        $result = Get-LidarrArtist -Filter "^The"
        
        $result | Should -HaveCount 1
        $result.artistName | Should -Be "The Beatles"
    }
    
    It "Should filter by monitored status" {
        $result = Get-LidarrArtist -Monitored:$true
        
        $result | Should -HaveCount 2
        $result | ForEach-Object { $_.monitored | Should -BeTrue }
        $result[0].artistName | Should -Be "Adele"
        $result[1].artistName | Should -Be "The Beatles"
    }
    
    It "Should sort artists by specified property" {
        $result = Get-LidarrArtist -SortBy Name
        
        $result | Should -HaveCount 3
        $result[0].artistName | Should -Be "Adele"
    }
}