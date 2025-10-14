BeforeAll {
    # Import the module
    $ModulePath = "$PSScriptRoot\.."
    Import-Module $ModulePath -Force
}

Describe "Get-LidarrAlbum" {
    BeforeEach {
        # Mock albums data
        $mockAlbums = @(
            @{
                id = 65
                artistId = 1
                title = "21"
                releaseDate = "2011-01-19T00:00:00Z"
                monitored = $true
                ratings = @{
                    votes = 1000
                    value = 8.5
                }
                statistics = @{
                    trackCount = 11
                    trackFileCount = 11
                }
            },
            @{
                id = 66
                artistId = 1
                title = "25"
                releaseDate = "2015-11-20T00:00:00Z"
                monitored = $true
                ratings = @{
                    votes = 950
                    value = 8.0
                }
                statistics = @{
                    trackCount = 11
                    trackFileCount = 11
                }
            },
            @{
                id = 67
                artistId = 2
                title = "Abbey Road"
                releaseDate = "1969-09-26T00:00:00Z"
                monitored = $true
                ratings = @{
                    votes = 5000
                    value = 9.8
                }
                statistics = @{
                    trackCount = 17
                    trackFileCount = 17
                }
            },
            @{
                id = 68
                artistId = 3
                title = "Dark Side of the Moon"
                releaseDate = "1973-03-01T00:00:00Z"
                monitored = $false
                ratings = @{
                    votes = 7500
                    value = 9.9
                }
                statistics = @{
                    trackCount = 10
                    trackFileCount = 10
                }
            }
        )
        
        # Mock artists data
        $mockArtists = @(
            @{
                id = 1
                artistName = "Adele"
                monitored = $true
            },
            @{
                id = 2
                artistName = "The Beatles"
                monitored = $true
            },
            @{
                id = 3
                artistName = "Pink Floyd"
                monitored = $false
            }
        )
        
        # Setup connection
        $Script:LidarrConnection = @{
            BaseUrl = "http://localhost:8686"
            ApiKey = "testapikey123"
            WebSession = $null
        }
        
        # Mock all albums
        Mock -CommandName Invoke-LidarrApi -ModuleName LidarrPS -ParameterFilter {
            $Endpoint -eq "album"
        } -MockWith {
            return $mockAlbums
        }
        
        # Mock specific album
        Mock -CommandName Invoke-LidarrApi -ModuleName LidarrPS -ParameterFilter {
            $Endpoint -match "album/\d+$"
        } -MockWith {
            $id = [int]($Endpoint -replace "album/", "")
            return $mockAlbums | Where-Object { $_.id -eq $id }
        }
        
        # Mock albums by artist id
        Mock -CommandName Invoke-LidarrApi -ModuleName LidarrPS -ParameterFilter {
            $Endpoint -match "album\?artistId=\d+"
        } -MockWith {
            $artistId = [int]($Endpoint -replace "album\?artistId=", "")
            return $mockAlbums | Where-Object { $_.artistId -eq $artistId }
        }
        
        # Mock artist
        Mock -CommandName Invoke-LidarrApi -ModuleName LidarrPS -ParameterFilter {
            $Endpoint -match "artist/\d+$"
        } -MockWith {
            $id = [int]($Endpoint -replace "artist/", "")
            return $mockArtists | Where-Object { $_.id -eq $id }
        }
    }
    
    It "Should get all albums" {
        $result = Get-LidarrAlbum
        
        $result | Should -HaveCount 4
        $result[0].title | Should -Be "21"
    }
    
    It "Should get album by ID" {
        $result = Get-LidarrAlbum -AlbumIds 67
        
        $result | Should -HaveCount 1
        $result.title | Should -Be "Abbey Road"
        $result.artistId | Should -Be 2
    }
    
    It "Should get albums by artist ID" {
        $result = Get-LidarrAlbum -ArtistId 1
        
        $result | Should -HaveCount 2
        $result[0].title | Should -Be "21"
        $result[1].title | Should -Be "25"
    }
    
    It "Should get albums by title" {
        $result = Get-LidarrAlbum -Title "Dark"
        
        $result | Should -HaveCount 1
        $result.title | Should -Be "Dark Side of the Moon"
    }
    
    It "Should filter by monitored status" {
        $result = Get-LidarrAlbum -Monitored:$false
        
        $result | Should -HaveCount 1
        $result.monitored | Should -BeFalse
        $result.title | Should -Be "Dark Side of the Moon"
    }
}