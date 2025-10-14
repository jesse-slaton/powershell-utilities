BeforeAll {
    # Import the module
    $ModulePath = "$PSScriptRoot\.."
    Import-Module $ModulePath -Force
}

Describe "Set-LidarrMonitoring" {
    BeforeEach {
        # Mock data
        $mockAlbum = @{
            id = 65
            artistId = 1
            title = "21"
            releaseDate = "2011-01-19T00:00:00Z"
            monitored = $true
            ratings = @{
                votes = 1000
                value = 8.5
            }
        }
        
        $mockArtist = @{
            id = 1
            artistName = "Adele"
            monitored = $true
        }
        
        # Setup connection
        $Script:LidarrConnection = @{
            BaseUrl = "http://localhost:8686"
            ApiKey = "testapikey123"
            WebSession = $null
        }
        
        # Mock GET for album
        Mock -CommandName Invoke-LidarrApi -ModuleName LidarrPS -ParameterFilter {
            $Endpoint -eq "album/65" -and $Method -eq "GET"
        } -MockWith {
            return $mockAlbum
        }
        
        # Mock GET for artist
        Mock -CommandName Invoke-LidarrApi -ModuleName LidarrPS -ParameterFilter {
            $Endpoint -eq "artist/1" -and $Method -eq "GET"
        } -MockWith {
            return $mockArtist
        }
        
        # Mock PUT for album
        Mock -CommandName Invoke-LidarrApi -ModuleName LidarrPS -ParameterFilter {
            $Endpoint -eq "album/65" -and $Method -eq "PUT"
        } -MockWith {
            # Update the mock album to match submitted changes
            $mockAlbum.monitored = ($Body | ConvertFrom-Json).monitored
            return $mockAlbum
        }
        
        # Mock PUT for artist
        Mock -CommandName Invoke-LidarrApi -ModuleName LidarrPS -ParameterFilter {
            $Endpoint -eq "artist/1" -and $Method -eq "PUT"
        } -MockWith {
            # Update the mock artist to match submitted changes
            $mockArtist.monitored = ($Body | ConvertFrom-Json).monitored
            return $mockArtist
        }
    }
    
    It "Should unmonitor an album by ID" {
        Set-LidarrMonitoring -AlbumIds 65 -Monitored $false -Confirm:$false
        
        # Verify API was called with PUT
        Should -Invoke -CommandName Invoke-LidarrApi -ModuleName LidarrPS -Times 1 -ParameterFilter {
            $Endpoint -eq "album/65" -and $Method -eq "PUT"
        }
    }
    
    It "Should monitor an album by ID" {
        # First set to false to ensure we're testing real change
        Set-LidarrMonitoring -AlbumIds 65 -Monitored $false -Confirm:$false
        
        # Now set back to true
        Set-LidarrMonitoring -AlbumIds 65 -Monitored $true -Confirm:$false
        
        # Verify the last PUT call had monitored=true
        Should -Invoke -CommandName Invoke-LidarrApi -ModuleName LidarrPS -Times 1 -ParameterFilter {
            $Endpoint -eq "album/65" -and $Method -eq "PUT" -and 
            ($Body | ConvertFrom-Json).monitored -eq $true
        }
    }
    
    It "Should accept album object from pipeline" {
        $album = @{ id = 65; title = "21"; artistId = 1 } | 
            ConvertTo-Json | ConvertFrom-Json
            
        $album | Set-LidarrMonitoring -Monitored $false -Confirm:$false
        
        # Verify API was called with PUT
        Should -Invoke -CommandName Invoke-LidarrApi -ModuleName LidarrPS -Times 1 -ParameterFilter {
            $Endpoint -eq "album/65" -and $Method -eq "PUT"
        }
    }
    
    It "Should return updated object with -PassThru" {
        $result = Set-LidarrMonitoring -AlbumIds 65 -Monitored $false -PassThru -Confirm:$false
        
        $result | Should -Not -BeNullOrEmpty
        $result.monitored | Should -BeFalse
        $result.title | Should -Be "21"
    }
}