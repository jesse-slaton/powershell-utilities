<#
.SYNOPSIS
    Reports the computer's approximate street address, coordinates and public IP address as one pipe-delimited line.

.DESCRIPTION
    Starts a System.Device.Location.GeoCoordinateWatcher and waits until it is Ready or
    location permission is Denied. If permission is denied, writes the error
    "Access Denied for Location Information" and stops.

    Otherwise it reads the latitude and longitude, gets the public IP address from
    http://ifconfig.me/ip, and reverse-geocodes the full-precision coordinates with the
    OpenStreetMap Nominatim service. Outputs one line in this form:
    <Road>|<City>|<State>|<CountryCode>|<Latitude>|<Longitude>|<PublicIP>
    with latitude and longitude rounded to two decimal places. Fields the service does
    not return are empty. Changes nothing.

.EXAMPLE
    .\GetLocation.ps1

    Outputs the address, rounded coordinates and public IP of the computer.

.NOTES
    Requires Windows location services to be on and allowed for desktop apps, and
    network access to ifconfig.me and nominatim.openstreetmap.org (the exact
    coordinates are sent to Nominatim). The wait loop has no timeout. Uses the
    System.Device assembly from .NET Framework, so run it in Windows PowerShell 5.1.
    No admin rights needed.
#>
Add-Type -AssemblyName System.Device #Required to access System.Device.Location namespace
$GeoWatcher = New-Object System.Device.Location.GeoCoordinateWatcher #Create the required object
$GeoWatcher.Start() #Begin resolving current locaton

while (($GeoWatcher.Status -ne 'Ready') -and ($GeoWatcher.Permission -ne 'Denied')) {
    Start-Sleep -Milliseconds 100 #Wait for discovery.
}

if ($GeoWatcher.Permission -eq 'Denied') {
    Write-Error 'Access Denied for Location Information'
}
else {
    $lat = $GeoWatcher.Position.Location.Latitude.ToString()
    $long = $GeoWatcher.Position.Location.Longitude.ToString()
    $roundlat = [math]::round($Geowatcher.Position.Location.Latitude,2)
    $roundlong = [math]::round($GeoWatcher.Position.Location.Longitude,2)
    $PubIP = Invoke-RestMethod -uri 'http://ifconfig.me/ip'
    $Location = Invoke-RestMethod -Uri "https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$long&format=jsonv2&addressdetails=1"
    Write-Output "$($location.address.road)|$($location.address.city)|$($location.address.state)|$($location.address.country_code)|$roundlat|$roundlong|$PubIP"
}