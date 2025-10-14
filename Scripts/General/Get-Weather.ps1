Function Get-Weather {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [string] $ZipCode
        , [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [string] $Country
        , [Parameter(Mandatory = $false)] [ValidateSet('metric','imperial')] [string] $units
        )
   
    $Country = $country.ToLower()
    $ApiToken = "$env:WEATHER_API_TOKEN"
    $Direction = "N", "NE", "E", "SE", "S", "SW", "W", "NW", "N"
    If (!($units)) {$units = 'imperial'}
    $url = "https://api.openweathermap.org/data/2.5/weather?zip=$($ZipCode),$($Country)&appid=$($ApiToken)&units=$($units)"

    Try {
        $Webrequest = Invoke-WebRequest -Uri $url -Method Get -ErrorAction Stop

        if ($Webrequest.StatusCode -eq 200) {

            $json = ConvertFrom-Json -InputObject $($Webrequest.Content)

            $date = Get-Date "1/1/1970"
            $date = $date.AddSeconds($($json.timezone))

            $Weatherobject = [PSCustomObject]@{
                City      = "$($json.name)"
                Sunrise   = [System.DateTimeOffset]::FromUnixTimeSeconds($json.sys.sunrise + $json.timezone).DateTime
                Sunset    = [System.DateTimeOffset]::FromUnixTimeSeconds($json.sys.sunset + $json.timezone).DateTime
                Temp      = [math]::Round($json.main.temp)
                Condition = "$($json.weather.main) ($($json.weather.description))"
                WindSpeed = $json.wind.speed
                WindDirection = $Direction[[Math]::Round($json.wind.deg / 45)]
            }

            return $Weatherobject
        }
        else {
            Write-Verbose "HTTP CODE : $($Webrequest.StatusCode)"
            return $Null
        }
    }
    Catch {
        Write-Verbose "ERROR: $($_)"
        return $NULL
    }
}