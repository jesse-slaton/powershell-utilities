function Connect-Lidarr {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,
        
        [Parameter(Mandatory = $true)]
        [string]$ApiKey,
        
        [Parameter()]
        [switch]$PassThru,
        
        [Parameter()]
        [switch]$Force
    )
    
    # Validate and clean up BaseUrl
    if (-not $BaseUrl.StartsWith('http://') -and -not $BaseUrl.StartsWith('https://')) {
        $BaseUrl = "http://$BaseUrl"
    }
    
    # Remove trailing slash if present
    $BaseUrl = $BaseUrl.TrimEnd('/')
    
    # Check if already connected and force not specified
    if ($Script:LidarrConnection.BaseUrl -and $Script:LidarrConnection.ApiKey -and -not $Force) {
        Write-Warning "Already connected to Lidarr at $($Script:LidarrConnection.BaseUrl). Use -Force to reconnect."
        
        if ($PassThru) {
            return $Script:LidarrConnection
        }
        
        return
    }
    
    # Store connection information
    $Script:LidarrConnection.BaseUrl = $BaseUrl
    $Script:LidarrConnection.ApiKey = $ApiKey
    $Script:LidarrConnection.WebSession = $null
    
    # Verify the connection by making a test call
    try {
        $systemStatus = Invoke-LidarrApi -Endpoint 'system/status'
        Write-Verbose "Successfully connected to Lidarr version $($systemStatus.version)"
        
        if ($PassThru) {
            return $Script:LidarrConnection
        }
        
        Write-Host "Successfully connected to Lidarr at $BaseUrl (Version: $($systemStatus.version))" -ForegroundColor Green
    }
    catch {
        # Reset connection variables on failure
        $Script:LidarrConnection.BaseUrl = $null
        $Script:LidarrConnection.ApiKey = $null
        $Script:LidarrConnection.WebSession = $null
        
        throw "Failed to connect to Lidarr: $_"
    }
}