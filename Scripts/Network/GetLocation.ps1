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