<#
.SYNOPSIS
    Defines Get-Weather, which returns the current weather for a postal code from OpenWeatherMap.

.DESCRIPTION
    Defines the Get-Weather function and does nothing else: running the script without
    dot-sourcing it produces no output and leaves nothing defined. The function queries
    the OpenWeatherMap current-weather API and returns an object with the city,
    sunrise, sunset, temperature, condition and wind. See Get-Help Get-Weather -Full
    for its parameters.

.EXAMPLE
    . .\Get-Weather.ps1
    $env:WEATHER_API_TOKEN = '<ApiKey>'
    Get-Weather -ZipCode 10001 -Country US

    Dot-sources the script, sets the API key for the session, and gets the weather.

.NOTES
    Needs network access to api.openweathermap.org and an OpenWeatherMap API key in
    the WEATHER_API_TOKEN environment variable. Works in Windows PowerShell 5.1 and
    PowerShell 7. No admin rights needed.
#>


Function Get-Weather {
    <#
    .SYNOPSIS
        Returns the current weather for a postal code from the OpenWeatherMap API.

    .DESCRIPTION
        Calls https://api.openweathermap.org/data/2.5/weather with the zip code,
        country code, units and the API key in $env:WEATHER_API_TOKEN. On HTTP 200 it
        returns one object with City, Sunrise and Sunset (the API's Unix times shifted
        by the location's UTC offset, as DateTime values), Temp (rounded), Condition
        ("<main> (<description>)"), WindSpeed and WindDirection (one of N, NE, E, SE,
        S, SW, W, NW). On any other status or on an error it returns $null and writes
        the reason only to the verbose stream.

    .PARAMETER ZipCode
        Postal code to look up, for example 10001.

    .PARAMETER Country
        Two-letter country code, for example US. It is converted to lower case.

    .PARAMETER units
        metric or imperial. Defaults to imperial (Fahrenheit, miles per hour) when
        omitted.

    .EXAMPLE
        Get-Weather -ZipCode 10001 -Country US

        Returns the current weather for that zip code in imperial units.

    .EXAMPLE
        Get-Weather -ZipCode 75001 -Country FR -units metric -Verbose

        Returns the weather in metric units and shows the error, if any, as verbose
        output.
    #>
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