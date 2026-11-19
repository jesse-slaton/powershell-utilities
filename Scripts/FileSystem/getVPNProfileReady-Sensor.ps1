<#
.SYNOPSIS
    Outputs 'ready' or 'not ready' for the IP Helper service and AnyConnect profile check.

.DESCRIPTION
    Outputs 'ready' when the IP Helper service (iphlpsvc) has StartType Automatic and is
    running, and the AnyConnect profile check passes; otherwise outputs 'not ready'.

    The profile check runs -notmatch '<AllowLocalProxyConnections>false' against the
    file objects that Get-Item returns for
    C:\ProgramData\Cisco\Cisco AnyConnect Secure Mobility Client\Profile\*.xml, which
    compares their names, not their contents. In practice it does not detect a profile
    with AllowLocalProxyConnections set to false, so the result depends on the
    iphlpsvc check. Read-only.

.EXAMPLE
    .\getVPNProfileReady-Sensor.ps1

    ready

.NOTES
    Written as a Tanium sensor. Needs PowerShell 5.0 or later (the StartType property
    of Get-Service). No admin rights needed. Set-MIGVPNProfile.ps1 makes the profile
    change this check is meant to verify.
#>
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