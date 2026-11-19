<#
.SYNOPSIS
    Reads account, device, group and device status data from the Crestron XiO Cloud API into variables.

.DESCRIPTION
    Reads the account ID and API key from the CRESTRON_XIO_ACCOUNT_ID and
    CRESTRON_XIO_API_KEY environment variables and sends the key in the
    XiO-subscription-key header. Calls the XiO Cloud API at https://api.crestron.io/api/V1
    to fetch the account, its devices and its groups into $Account, $Devices and
    $Groups, then fetches the status of each device (by device-cid) into
    $DeviceStatus, waiting 120 seconds after each status call.

    The script writes nothing to the pipeline. To use the data, dot-source it so the
    variables stay in your session. Changes nothing on the remote side (GET requests
    only).

.EXAMPLE
    $env:CRESTRON_XIO_ACCOUNT_ID = '<AccountId>'
    $env:CRESTRON_XIO_API_KEY = '<ApiKey>'
    . .\Get-CrestronAPIData.ps1
    $DeviceStatus

    Dot-sources the script and shows the collected device status records.

.NOTES
    Requires a Crestron XiO Cloud account and API subscription key, supplied through
    the two environment variables above (no credentials are stored in the script), and
    network access to api.crestron.io. Runtime is at least two minutes per device. No
    admin rights needed. Works in Windows PowerShell 5.1 and PowerShell 7.
#>
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