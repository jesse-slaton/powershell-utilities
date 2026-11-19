<#
.SYNOPSIS
    Disables and re-enables every monitor device to reset the displays.

.DESCRIPTION
    Finds all Win32_PnPEntity devices whose Service is "monitor". For each one it runs
    Disable-PnpDevice, waits 2 seconds, then runs Enable-PnpDevice (both with
    -Confirm:$false). Screens may go blank briefly while this runs. Writes
    "Monitor reset process completed." with Write-Host when done.

.EXAMPLE
    .\ResetDisplay.ps1

    Monitor reset process completed.

.NOTES
    Requires administrator rights (Disable-PnpDevice and Enable-PnpDevice) and the
    PnpDevice module that ships with Windows 8 / Server 2012 and later. Changes device
    state.
#>

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