function Invoke-LidarrApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint,
        
        [Parameter()]
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE')]
        [string]$Method = 'GET',
        
        [Parameter()]
        [object]$Body
    )
    
    # Check for valid connection
    if (-not $Script:LidarrConnection.BaseUrl -or -not $Script:LidarrConnection.ApiKey) {
        throw "Not connected to Lidarr. Please use Connect-Lidarr first."
    }
    
    # Build request URL
    $url = "$($Script:LidarrConnection.BaseUrl)/api/v1/$Endpoint"
    
    # Add API key as query parameter
    $apiKey = $Script:LidarrConnection.ApiKey
    $url += if ($url.Contains('?')) { "&apikey=$apiKey" } else { "?apikey=$apiKey" }
    
    # Build invoke parameters
    $invokeParams = @{
        Uri = $url
        Method = $Method
        ContentType = 'application/json'
        ErrorAction = 'Stop'
    }
    
    # Add web session if exists
    if ($Script:LidarrConnection.WebSession) {
        $invokeParams['WebSession'] = $Script:LidarrConnection.WebSession
    }
    else {
        $invokeParams['SessionVariable'] = 'LidarrSession'
    }
    
    # Add body if specified
    if ($Body) {
        if ($Body -is [string]) {
            $invokeParams['Body'] = $Body
        }
        else {
            $invokeParams['Body'] = $Body | ConvertTo-Json -Depth 10
        }
    }
    
    # Execute request
    try {
        $response = Invoke-RestMethod @invokeParams
        
        # Store session if not already stored
        if (-not $Script:LidarrConnection.WebSession -and $LidarrSession) {
            $Script:LidarrConnection.WebSession = $LidarrSession
        }
        
        return $response
    }
    catch {
        # Handle common HTTP errors with user-friendly messages
        $statusCode = $_.Exception.Response.StatusCode.value__
        $statusDescription = $_.Exception.Response.ReasonPhrase
        
        $errorMessage = switch ($statusCode) {
            401 { "Authentication error: API key is invalid or missing" }
            404 { "Resource not found: $Endpoint" }
            500 { "Lidarr server error: $statusDescription" }
            default { "Error accessing Lidarr API: $statusDescription ($statusCode)" }
        }
        
        throw $errorMessage
    }
}