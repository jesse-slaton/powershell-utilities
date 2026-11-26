function Get-GeoIP {
    <#
    .Synopsis
    Resolve IPAddress Geo IP Location
    .Description
    This Function Queries The IP API With Supplied IPAdderess And Returns Geo IP Location
    .Parameter IPAddress
    IPAddressTo Be Resolved
    .Example
    Get-GeoIP -IPAddress 96.23.36.24
    .Example
    Get-GeoIP -IPAddress 8.8.8.8, 1.1.1.1
    .Example
    $IP = (Get-NetTCPConnection).remoteaddress | Where-Object {$_ -notmatch '0.0.0.0|:'}
    Get-GeoIP -IPAddress $IP
    .Notes
    Requires outbound network access to the ip-api.com JSON geolocation web service
    (http://ip-api.com/json/<IP>), an external third-party service: every address
    looked up is sent to it, over plain HTTP. No API key is used. The function waits
    one second after each lookup, so N addresses take at least N seconds.
    Needs Invoke-RestMethod (Windows PowerShell 3.0 or later, or PowerShell 7). No
    admin rights needed.

    This file only defines the function; dot-source it before calling Get-GeoIP.

    Each address must be a whole dotted IPv4 address (four octets, 0 to 255); any
    other string, including an IPv6 address, is rejected before any lookup. A failed
    lookup (no network, an HTTP error) writes a warning ('<IP> : <error>') and no
    object, then the next address is looked up.

    Known issue (not fixed here): the service's status field is not checked, so a
    lookup it refuses (such as a private or reserved address) still returns an
    object, with empty location fields.
    #>
    [CmdletBinding()]
    param(
        [Parameter (Mandatory = $true,
            ValueFromPipeline = $false)]
        # Anchored (\A ... \z) so the whole string must be the address; each octet is 0-255.
        [ValidatePattern('\A(?:(?:25[0-5]|2[0-4]\d|1\d\d|0?[1-9]\d|0{0,2}\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|0?[1-9]\d|0{0,2}\d)\z')]
        [string[]]$IPAddress
    )
    begin {
        $CurrentIP = 0
    }
    process {    
        foreach ($IP in $IPAddress) {
            $CurrentIP++
            Write-Progress -Activity "Resoving IPAddress: $IP" -Status "$CurrentIP of $($IPAddress.Count)" -PercentComplete (($CurrentIP / $IPAddress.Count) * 100)
            try {
                Write-Verbose 'Sending Request to http://ip-api.com/json/'
                # -ErrorAction Stop so every failure, terminating or not, reaches the catch block's warning.
                Invoke-RestMethod -Method Get -Uri "http://ip-api.com/json/$IP" -ErrorAction Stop | Foreach-object {
                    [pscustomobject]@{
                        IPAddress     = $IP
                        Country       = $_.Country
                        CountryCode   = $_.CountryCode
                        Region        = $_.Region
                        RegionName    = $_.RegionName
                        City          = $_.City
                        'Postal Code' = $_.Zip
                        Org           = $_.Org
                        ISP           = $_.ISP
                        as            = $_.as
                        Query         = $_.Query
                        Lat           = $_.Lat
                        Lon           = $_.Lon
                        TimeZone      = $_.TimeZone
                    }
                }
            }
            catch {
                Write-Warning -Message "$IP : $_"
            }
            Start-Sleep -Seconds 1
        }
    }
    end { }
        
}