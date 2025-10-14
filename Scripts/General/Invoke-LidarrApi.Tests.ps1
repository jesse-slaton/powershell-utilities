BeforeAll {
    # Import the module
    $ModulePath = "$PSScriptRoot\.."
    Import-Module $ModulePath -Force
}

Describe "Invoke-LidarrApi" {
    BeforeEach {
        # Setup mock for Invoke-RestMethod
        Mock -CommandName Invoke-RestMethod -MockWith {
            return @{
                result = "Success"
            }
        }
        
        # Initialize connection
        $Script:LidarrConnection = @{
            BaseUrl = "http://localhost:8686"
            ApiKey = "testapikey123"
            WebSession = $null
        }
    }
    
    It "Should throw if not connected" {
        # Clear connection
        $Script:LidarrConnection.BaseUrl = $null
        $Script:LidarrConnection.ApiKey = $null
        
        { Invoke-LidarrApi -Endpoint "system/status" } | Should -Throw "Not connected to Lidarr"
    }
    
    It "Should call Invoke-RestMethod with correct parameters for GET" {
        Invoke-LidarrApi -Endpoint "system/status"
        
        Should -Invoke -CommandName Invoke-RestMethod -Times 1 -ParameterFilter {
            $Uri -eq "http://localhost:8686/api/v1/system/status?apikey=testapikey123" -and
            $Method -eq "GET"
        }
    }
    
    It "Should call Invoke-RestMethod with correct parameters for POST with body" {
        $body = @{name = "Test"; value = 123}
        Invoke-LidarrApi -Endpoint "test" -Method "POST" -Body $body
        
        Should -Invoke -CommandName Invoke-RestMethod -Times 1 -ParameterFilter {
            $Uri -eq "http://localhost:8686/api/v1/test?apikey=testapikey123" -and
            $Method -eq "POST" -and
            $Body -match "name" -and
            $Body -match "Test" -and
            $Body -match "value" -and 
            $Body -match "123"
        }
    }
    
    It "Should handle errors from the API" {
        Mock -CommandName Invoke-RestMethod -MockWith {
            $response = New-Object System.Net.Http.HttpResponseMessage 404
            $response.ReasonPhrase = "Not Found"
            $exception = New-Object Microsoft.PowerShell.Commands.HttpResponseException "Response status code does not indicate success: 404 (Not Found).", $response
            throw $exception
        }
        
        { Invoke-LidarrApi -Endpoint "nonexistent" } | Should -Throw "Resource not found"
    }
}