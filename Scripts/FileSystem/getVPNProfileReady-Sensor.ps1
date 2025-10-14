$iphlpsvcReady = (Get-Service iphlpsvc).StartType -eq 'automatic' -and (Get-Service iphlpsvc).Status -eq 'running'
#$content = Get-Item "$env:ProgramData\Cisco\Cisco AnyConnect Secure Mobility Client\Profile\*.xml" | ForEach-Object {Get-Content $_}
#$vpnProfileReady = '<AllowLocalProxyConnections>false' -notin $content
$vpnProfileReady = (Get-Item 'C:\ProgramData\Cisco\Cisco AnyConnect Secure Mobility Client\Profile\*.xml') -notmatch '<AllowLocalProxyConnections>false'
if ($iphlpsvcReady -and $vpnProfileReady) {
    Write-Output 'ready'
}
else {
    Write-Output 'not ready'
}