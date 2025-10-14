# Get all monitor instances
$monitors = Get-CimInstance -Namespace root\CIMV2 -ClassName Win32_PnPEntity | Where-Object { $_.Service -eq "monitor" }


foreach ($monitor in $monitors) {
    # Get the monitor's device ID
    $deviceId = $monitor.DeviceID

    # Disable the monitor
    Disable-PnpDevice -InstanceId $deviceId -Confirm:$false

    # Wait for a moment
    Start-Sleep -Seconds 2

    # Re-enable the monitor
    Enable-PnpDevice -InstanceId $deviceId -Confirm:$false
}

Write-Host "Monitor reset process completed."