BeforeAll {
    # Import the module
    $ModulePath = "$PSScriptRoot\.."
    Import-Module $ModulePath -Force
}

Describe "Connect-Lidarr" {
    BeforeEach {
        # Mock Invoke-LidarrApi to return a successful system status
        Mock -CommandName Invoke-LidarrApi -ModuleName LidarrPS -MockWith {
            return @{
                version = "2.12.1.46635"
                appName = "Lidarr"
                isDebug = $false
                isProduction = $true
                isAdmin = $true
                isNetCore = $true
            }
        }
        
        # Reset connection variables
        $Script:LidarrConnection.BaseUrl = $null
        $Script:LidarrConnection.ApiKey = $null
        $Script:LidarrConnection.WebSession = $null
    }
    
    It "Should set connection info and validate" {
        Connect-Lidarr -BaseUrl "http://localhost:8686" -ApiKey "testapikey123"
        
        # Check connection info was set correctly
        $Script:LidarrConnection.BaseUrl | Should -Be "http://localhost:8686"
        $Script:LidarrConnection.ApiKey | Should -Be "testapikey123"
        
        # Verify API was called
        Should -Invoke -CommandName Invoke-LidarrApi -ModuleName LidarrPS -Times 1 -ParameterFilter {
            $Endpoint -eq 'system/status'
        }
    }
    
    It "Should add http:// if missing from BaseUrl" {
        Connect-Lidarr -BaseUrl "localhost:8686" -ApiKey "testapikey123"
        
        $Script:LidarrConnection.BaseUrl | Should -Be "http://localhost:8686"
    }
    
    It "Should remove trailing slash from BaseUrl" {
        Connect-Lidarr -BaseUrl "http://localhost:8686/" -ApiKey "testapikey123"
        
        $Script:LidarrConnection.BaseUrl | Should -Be "http://localhost:8686"
    }
    
    It "Should warn if already connected without -Force" {
        # First connection
        Connect-Lidarr -BaseUrl "http://localhost:8686" -ApiKey "testapikey123"
        
        # Mock Write-Warning to capture it
        Mock -CommandName Write-Warning -MockWith { }
        
        # Second connection without -Force
        Connect-Lidarr -BaseUrl "http://localhost:9999" -ApiKey "differentkey"
        
        # Should still have the original connection
        $Script:LidarrConnection.BaseUrl | Should -Be "http://localhost:8686"
        
        # Should have warned
        Should -Invoke -CommandName Write-Warning -Times 1
    }
    
    It "Should reconnect with -Force" {
        # First connection
        Connect-Lidarr -BaseUrl "http://localhost:8686" -ApiKey "testapikey123"
        
        # Second connection with -Force
        Connect-Lidarr -BaseUrl "http://localhost:9999" -ApiKey "differentkey" -Force
        
        # Should have the new connection
        $Script:LidarrConnection.BaseUrl | Should -Be "http://localhost:9999"
        $Script:LidarrConnection.ApiKey | Should -Be "differentkey"
    }
    
    It "Should handle connection failures" {
        # Make Invoke-LidarrApi throw
        Mock -CommandName Invoke-LidarrApi -ModuleName LidarrPS -MockWith {
            throw "Connection error"
        }
        
        # Should throw and reset connection info
        { Connect-Lidarr -BaseUrl "http://localhost:8686" -ApiKey "testapikey123" } | 
            Should -Throw "Failed to connect to Lidarr"
            
        $Script:LidarrConnection.BaseUrl | Should -BeNullOrEmpty
        $Script:LidarrConnection.ApiKey | Should -BeNullOrEmpty
    }
}