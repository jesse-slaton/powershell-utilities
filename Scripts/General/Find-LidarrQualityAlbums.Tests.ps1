BeforeAll {
    # Import the module
    $ModulePath = "$PSScriptRoot\.."
    Import-Module $ModulePath -Force
}

Describe "Find-LidarrQualityAlbums" {
    BeforeEach {
        # Mock albums data
        $mockAlbums = @(
            @{
                id = 65
                artistId = 1
                title = "21"
                releaseDate = "2011-01-19T00:00:00Z"
                monitored = $true
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
                statistics = @{
                    trackCount = 11
                    trackFileCount = 10  # Not complete
                }
            },
            @{
                id = 67
                artistId = 2
                title = "Abbey Road"
                releaseDate = "1969-09-26T00:00:00Z"
                monitored = $true
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
                statistics = @{
                    trackCount = 10
                    trackFileCount = 10
                }
            }
        )
        
        # Mock track files
        $mockTrackFiles = @(
            # 24-bit FLAC files (Album 65: 21 by Adele)
            @{ 
                id = 101
                albumId = 65
                trackId = 1001
                path = "/music/Adele/21/01. Rolling in the Deep.flac"
                quality = @{ quality = @{ name = "FLAC 24bit" } }
                mediaInfo = @{ audioBitDepth = 24; audioFormat = "FLAC" }
            },
            @{ 
                id = 102
                albumId = 65
                trackId = 1002
                path = "/music/Adele/21/02. Rumour Has It.flac"
                quality = @{ quality = @{ name = "FLAC 24bit" } }
                mediaInfo = @{ audioBitDepth = 24; audioFormat = "FLAC" }
            },
            @{ 
                id = 103
                albumId = 65
                trackId = 1003
                path = "/music/Adele/21/03. Turning Tables.flac"
                quality = @{ quality = @{ name = "FLAC 24bit" } }
                mediaInfo = @{ audioBitDepth = 24; audioFormat = "FLAC" }
            },
            @{ 
                id = 104
                albumId = 65
                trackId = 1004
                path = "/music/Adele/21/04. Don't You Remember.flac"
                quality = @{ quality = @{ name = "FLAC 24bit" } }
                mediaInfo = @{ audioBitDepth = 24; audioFormat = "FLAC" }
            },
            @{ 
                id = 105
                albumId = 65
                trackId = 1005
                path = "/music/Adele/21/05. Set Fire to the Rain.flac"
                quality = @{ quality = @{ name = "FLAC 24bit" } }
                mediaInfo = @{ audioBitDepth = 24; audioFormat = "FLAC" }
            },
            @{ 
                id = 106
                albumId = 65
                trackId = 1006
                path = "/music/Adele/21/06. He Won't Go.flac"
                quality = @{ quality = @{ name = "FLAC 24bit" } }
                mediaInfo = @{ audioBitDepth = 24; audioFormat = "FLAC" }
            },
            @{ 
                id = 107
                albumId = 65
                trackId = 1007
                path = "/music/Adele/21/07. Take It All.flac"
                quality = @{ quality = @{ name = "FLAC 24bit" } }
                mediaInfo = @{ audioBitDepth = 24; audioFormat = "FLAC" }
            },
            @{ 
                id = 108
                albumId = 65
                trackId = 1008
                path = "/music/Adele/21/08. I'll Be Waiting.flac"
                quality = @{ quality = @{ name = "FLAC 24bit" } }
                mediaInfo = @{ audioBitDepth = 24; audioFormat = "FLAC" }
            },
            @{ 
                id = 109
                albumId = 65
                trackId = 1009
                path = "/music/Adele/21/09. One and Only.flac"
                quality = @{ quality = @{ name = "FLAC 24bit" } }
                mediaInfo = @{ audioBitDepth = 24; audioFormat = "FLAC" }
            },
            @{ 
                id = 110
                albumId = 65
                trackId = 1010
                path = "/music/Adele/21/10. Lovesong.flac"
                quality = @{ quality = @{ name = "FLAC 24bit" } }
                mediaInfo = @{ audioBitDepth = 24; audioFormat = "FLAC" }
            },
            @{ 
                id = 111
                albumId = 65
                trackId = 1011
                path = "/music/Adele/21/11. Someone Like You.flac"
                quality = @{ quality = @{ name = "FLAC 24bit" } }
                mediaInfo = @{ audioBitDepth = 24; audioFormat = "FLAC" }
            },
            
            # Mix of qualities (Album 67: Abbey Road by The Beatles)
            @{ 
                id = 201
                albumId = 67
                trackId = 2001
                path = "/music/Beatles/Abbey Road/01. Come Together.flac"
                quality = @{ quality = @{ name = "FLAC" } }
                mediaInfo = @{ audioBitDepth = 16; audioFormat = "FLAC" }
            },
            @{ 
                id = 202
                albumId = 67
                trackId = 2002
                path = "/music/Beatles/Abbey Road/02. Something.flac"
                quality = @{ quality = @{ name = "FLAC 24bit" } }
                mediaInfo = @{ audioBitDepth = 24; audioFormat = "FLAC" }
            },
            
            # All 24-bit FLAC (Album 68: Dark Side of the Moon by Pink Floyd)
            @{ 
                id = 301
                albumId = 68
                trackId = 3001
                path = "/music/Pink Floyd/Dark Side of the Moon/01. Speak to Me.flac"
                quality = @{ quality = @{ name = "FLAC 24bit" } }
                mediaInfo = @{ audioBitDepth = 24; audioFormat = "FLAC" }
            },
            @{ 
                id = 302
                albumId = 68
                trackId = 3002
                path = "/music/Pink Floyd/Dark Side of the Moon/02. Breathe.flac"
                quality = @{ quality = @{ name = "FLAC 24bit" } }
                mediaInfo = @{ audioBitDepth = 24; audioFormat = "FLAC" }
            },
            @{ 
                id = 303
                albumId = 68
                trackId = 3003
                path = "/music/Pink Floyd/Dark Side of the Moon/03. On the Run.flac"
                quality = @{ quality = @{ name = "FLAC 24bit" } }
                mediaInfo = @{ audioBitDepth = 24; audioFormat = "FLAC" }
            },
            @{ 
                id = 304
                albumId = 68
                trackId = 3004
                path = "/music/Pink Floyd/Dark Side of the Moon/04. Time.flac"
                quality = @{ quality = @{ name = "FLAC 24bit" } }
                mediaInfo = @{ audioBitDepth = 24; audioFormat = "FLAC" }
            },
            @{ 
                id = 305
                albumId = 68
                trackId = 3005
                path = "/music/Pink Floyd/Dark Side of the Moon/05. The Great Gig in the Sky.flac"
                quality = @{ quality = @{ name = "FLAC 24bit" } }
                mediaInfo = @{ audioBitDepth = 24; audioFormat = "FLAC" }
            },
            @{ 
                id = 306
                albumId = 68
                trackId = 3006
                path = "/music/Pink Floyd/Dark Side of the Moon/06. Money.flac"
                quality = @{ quality = @{ name = "FLAC 24bit" } }
                mediaInfo = @{ audioBitDepth = 24; audioFormat = "FLAC" }
            },
            @{ 
                id = 307
                albumId = 68
                trackId = 3007
                path = "/music/Pink Floyd/Dark Side of the Moon/07. Us and Them.flac"
                quality = @{ quality = @{ name = "FLAC 24bit" } }
                mediaInfo = @{ audioBitDepth = 24; audioFormat = "FLAC" }
            },
            @{ 
                id = 308
                albumId = 68
                trackId = 3008
                path = "/music/Pink Floyd/Dark Side of the Moon/08. Any Colour You Like.flac"
                quality = @{ quality = @{ name = "FLAC 24bit" } }
                mediaInfo = @{ audioBitDepth = 24; audioFormat = "FLAC" }
            },
            @{ 
                id = 309
                albumId = 68
                trackId = 3009
                path = "/music/Pink Floyd/Dark Side of the Moon/09. Brain Damage.flac"
                quality = @{ quality = @{ name = "FLAC 24bit" } }
                mediaInfo = @{ audioBitDepth = 24; audioFormat = "FLAC" }
            },
            @{ 
                id = 310
                albumId = 68
                trackId = 3010
                path = "/music/Pink Floyd/Dark Side of the Moon/10. Eclipse.flac"
                quality = @{ quality = @{ name = "FLAC 24bit" } }
                mediaInfo = @{ audioBitDepth = 24; audioFormat = "FLAC" }
            }
        )
        
        # Mock artists
        $mockArtists = @(
            @{ id = 1; artistName = "Adele" },
            @{ id = 2; artistName = "The Beatles" },
            @{ id = 3; artistName = "Pink Floyd" }
        )
        
        # Setup connection
        $Script:LidarrConnection = @{
            BaseUrl = "http://localhost:8686"
            ApiKey = "testapikey123"
            WebSession = $null
        }
        
        # Mock calls
        Mock -CommandName Invoke-LidarrApi -ModuleName LidarrPS -ParameterFilter {
            $Endpoint -eq "album"
        } -MockWith {
            return $mockAlbums
        }
        
        Mock -CommandName Invoke-LidarrApi -ModuleName LidarrPS -ParameterFilter {
            $Endpoint -eq "trackfile"
        } -MockWith {
            return $mockTrackFiles
        }
        
        Mock -CommandName Invoke-LidarrApi -ModuleName LidarrPS -ParameterFilter {
            $Endpoint -match "artist/\d+"
        } -MockWith {
            $id = [int]($Endpoint -replace "artist/", "")
            return $mockArtists | Where-Object { $_.id -eq $id }
        }
        
        Mock -CommandName Invoke-LidarrApi -ModuleName LidarrPS -ParameterFilter {
            $Endpoint -match "album/\d+" -and $Method -eq "PUT"
        } -MockWith {
            $id = [int]($Endpoint -replace "album/", "")
            $albumToUpdate = $mockAlbums | Where-Object { $_.id -eq $id }
            $albumToUpdate.monitored = ($Body | ConvertFrom-Json).monitored
            return $albumToUpdate
        }
        
        # Mock Write-Host to avoid output in tests
        Mock -CommandName Write-Host -ModuleName LidarrPS -MockWith {}
    }
    
    It "Should find 24-bit albums" {
        $result = Find-LidarrQualityAlbums -QualityProfile "24bit" -PassThru
        
        $result | Should -HaveCount 2
        $result | ForEach-Object { $_.id } | Should -Contain 65  # Adele
        $result | ForEach-Object { $_.id } | Should -Contain 68  # Pink Floyd
    }
    
    It "Should only include complete albums when specified" {
        $result = Find-LidarrQualityAlbums -QualityProfile "24bit" -CompleteAlbumsOnly -PassThru
        
        $result | Should -HaveCount 2
        $result | ForEach-Object { $_.id } | Should -Contain 65  # Adele (complete)
        $result | ForEach-Object { $_.id } | Should -Contain 68  # Pink Floyd (complete)
    }
    
    It "Should filter by monitored status" {
        $result = Find-LidarrQualityAlbums -QualityProfile "24bit" -MonitoredOnly -PassThru
        
        $result | Should -HaveCount 1
        $result.id | Should -Be 65  # Only Adele is monitored
    }
    
    It "Should unmonitor albums when requested" {
        Find-LidarrQualityAlbums -QualityProfile "24bit" -UnmonitorAlbums -Confirm:$false
        
        # Verify PUT was called to update monitoring status
        Should -Invoke -CommandName Invoke-LidarrApi -ModuleName LidarrPS -Times 2 -ParameterFilter {
            $Method -eq "PUT" -and $Body -match '"monitored":false'
        }
    }
}