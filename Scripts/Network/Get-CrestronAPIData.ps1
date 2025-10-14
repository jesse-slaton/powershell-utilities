$CrestronAPIRootURL = 'https://api.crestron.io/api/V1'
$AccountID = $env:CRESTRON_XIO_ACCOUNT_ID
$APIKey = $env:CRESTRON_XIO_API_KEY

$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("XiO-subscription-key", "$APIKey")
$Account = Invoke-RestMethod "$CrestronAPIRootURL/account/accountid/$AccountID/account" -Headers $headers
$Devices = Invoke-RestMethod "$CrestronAPIRootURL/device/accountid/$AccountID/devices" -Headers $headers
$Groups = Invoke-RestMethod "$CrestronAPIRootURL/group/accountid/$AccountID/groups" -Headers $headers
$DeviceStatus = Foreach ($devicecid in $Devices.'device-cid') {
    Invoke-RestMethod "$CrestronAPIRootURL/device/accountid/$AccountID/devicecid/$devicecid/status" -Headers $headers
    Sleep 120
}