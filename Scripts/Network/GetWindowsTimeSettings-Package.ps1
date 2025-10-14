function ConvertToFriendlyTime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$Seconds
    )

    $TimeSpan = New-TimeSpan -Seconds $Seconds
    $OutputString = ""

    if ($TimeSpan.Days -gt 0) {
        $OutputString = "{0} {1}" -f $TimeSpan.Days, $(if ($TimeSpan.Days -eq 1) {"day"} else {"days"})
    } elseif ($TimeSpan.Hours -gt 0) {
        $OutputString = "{0} {1}" -f $TimeSpan.Hours, $(if ($TimeSpan.Hours -eq 1) {"hour"} else {"hours"})
    } elseif ($TimeSpan.Minutes -gt 0) {
        $OutputString = "{0} {1}" -f $TimeSpan.Minutes, $(if ($TimeSpan.Minutes -eq 1) {"minute"} else {"minutes"})
    } else {
        $OutputString = "{0} {1}" -f $TimeSpan.Seconds, $(if ($TimeSpan.Seconds -eq 1) {"second"} else {"seconds"})
    }

    # Round to the nearest day, hour, or minute
    switch ($OutputString) {
        { $_ -match "day" } { $OutputString = "{0} {1}" -f ([math]::Round($TimeSpan.TotalDays)), $(if ([math]::Round($TimeSpan.TotalDays) -eq 1) {"day"} else {"days"}) }
        { $_ -match "hour" } { $OutputString = "{0} {1}" -f ([math]::Round($TimeSpan.TotalHours)), $(if ([math]::Round($TimeSpan.TotalHours) -eq 1) {"hour"} else {"hours"}) }
        { $_ -match "minute" } { $OutputString = "{0} {1}" -f ([math]::Round($TimeSpan.TotalMinutes)), $(if ([math]::Round($TimeSpan.TotalMinutes) -eq 1) {"minute"} else {"minutes"}) }
    }

    return $OutputString
}

# Set the time server to time.windows.com
$NTPServer = (Get-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters -Name NtpServer).NtpServer

# Configure the time service to start automatically and sync every 15 minutes
$Interval = ConvertToFriendlyTime -Seconds $(Get-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient -Name SpecialPollInterval).SpecialPollInterval 
$ServiceStatus = (Get-Service -Name w32time).Status

Write-Output "$($NTPServer.Split(',')[0])|$($NTPServer.Split(',')[1])|$($Interval)|$($ServiceStatus)"