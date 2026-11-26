<#
.SYNOPSIS
Starts a Windows Performance Recorder (WPR) session.

.DESCRIPTION
Starts a WPR recording (wpr.exe -start <profile> -filemode) with the given profile, waits for the given duration, then stops it with wpr -stop, which writes an ETL file named <ComputerName>_<yyyy-MM-dd_HH-mm-ss>.etl to OutputPath. The profile is used at its Light detail level, or at its Verbose level when the script is run with -Verbose. Progress messages (start and stop times, the saved ETL path) are written to the output stream as strings.

If the script body throws (an invalid duration, or an OutputPath that does not exist), the error is written with Write-Error, and the script tries to append it to <ComputerName>_<yyyy-MM-dd_HH-mm-ss>.log in OutputPath. If wpr -start fails (for example, the session is not elevated, or another WPR trace is already running), that is reported the same way, and the script neither sleeps nor runs wpr -stop or wpr -cancel, so a trace someone else started is left alone. A failure of wpr -stop itself does not throw, so it is not reported this way.

.PARAMETER Duration
Specifies the duration as one or more whole numbers, each followed by a unit: h, hr, hrs, hour or hours; m, min, mins, minute or minutes; s, sec, secs, second or seconds (any case, spaces allowed). Examples: '1m', '300s', '1h30m', '5min', '10minutes', '30sec', '1hr', '2hours', '1 hour 30 min'. All parts are added up. Fractions ('1.5h'), negative numbers and bare numbers without a unit are rejected. Default is '5m'.

.PARAMETER WprProfile
Specifies the WPR profile to record from a predefined set of valid profiles. Default is 'GeneralProfile'.

.PARAMETER OutputPath
Specifies the output path for the ETL file. Default is the user's Desktop.

.EXAMPLE
.\StartWPRSession-Sensor.ps1 -Duration "30m" -WprProfile "CPU" -OutputPath "C:\ETLs"

This example starts a 30-minute recording session using the CPU profile and saves the ETL to C:\ETLs.

.EXAMPLE
.\StartWPRSession-Sensor.ps1

This example records the GeneralProfile for 5 minutes and saves the ETL to the current user's Desktop.

.NOTES
Requires Windows, wpr.exe on the PATH (included in Windows 10 and later, and in the Windows Performance Toolkit), and an elevated (admin) session, because WPR needs admin rights to start a trace. Runs on Windows PowerShell 5.1 and PowerShell 7.

If the script is stopped during the recording (Ctrl+C, or the pipeline is stopped), it cancels the trace with wpr -cancel, so no system-wide trace is left running and no ETL file is written. A process that is killed outright runs no cleanup; end such a trace with wpr -cancel.

Known issue (not fixed here): writing the error log fails when OutputPath itself does not exist.

For more information on Windows Performance Recorder, see the following:
https://docs.microsoft.com/en-us/windows-hardware/test/wpt/windows-performance-recorder

.LINK
https://docs.microsoft.com/en-us/windows-hardware/test/wpt/windows-performance-recorder

#>
[CmdletBinding()]
param(
    [string]$Duration = "5m",
    [ValidateSet("GeneralProfile", "CPU", "DiskIO", "FileIO", "Registry", "Network", "Heap", "Pool", "VirtualAllocation", "Audio", "Video", "Power", "InternetExplorer", "EdgeBrowser", "Minifilter", "GPU", "Handle", "XAMLActivity", "HTMLActivity", "DesktopComposition", "XAMLAppResponsiveness", "HTMLResponsiveness", "ReferenceSet", "ResidentSet", "XAMLHTMLAppMemoryAnalysis", "UTC", "DotNET", "WdfTraceLoggingProvider", "HeapSnapshot")]
    [string]$WprProfile = "GeneralProfile",
    [string]$OutputPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
)

function ConvertTo-Seconds {
    param([string]$InputDuration)

    # The whole string must be one or more <number><unit> parts, such as 1h30m or 5min; every
    # part counts. A unit is h/hr/hrs/hour/hours, m/min/mins/minute/minutes or s/sec/secs/second/seconds.
    $part = '(\d+)\s*(h(?:ours?|rs?)?|m(?:in(?:ute)?s?)?|s(?:ec(?:ond)?s?)?)'
    if ($InputDuration -notmatch "^\s*(?:$part\s*)+$") {
        throw "Invalid duration format. Please specify the duration in hours (h), minutes (m), or seconds (s), for example 1h30m."
    }

    $total = 0
    foreach ($match in [regex]::Matches($InputDuration, $part, 'IgnoreCase')) {
        $value = [int]$match.Groups[1].Value
        # The unit is keyed on its first letter.
        switch ($match.Groups[2].Value.Substring(0, 1)) {
            'h' { $total += $value * 3600 }
            'm' { $total += $value * 60 }
            's' { $total += $value }
        }
    }
    $total
}

function Invoke-Wpr {
    # Runs wpr.exe with the given arguments. A separate function so tests can mock it.
    param([string[]]$ArgumentList)

    & wpr.exe @ArgumentList
}

function InvokeWPRSession {
    <#
    .SYNOPSIS
    Invokes a WPR recording session.

    .DESCRIPTION
    Starts a WPR recording session with the specified profile. It runs the WPR process in the background hidden from the user.
    The function uses Start-Sleep to allow the recording to proceed for the specified duration and then stops the recording.

    'wpr -start' exits as soon as the trace is running, and the trace keeps recording until 'wpr -stop' ends it. So the
    function waits for 'wpr -start' to exit and checks its exit code, then uses Start-Sleep to let the trace record for the
    desired duration before issuing the stop command to end the recording session and produce the ETL file.

    If 'wpr -start' exits with a nonzero code (for example, another WPR trace is already running), the function throws
    before it sleeps, and runs neither 'wpr -stop' nor 'wpr -cancel', which would act on that other trace.

    .PARAMETER WprProfile
    The WPR profile to be used for the recording session.

    .PARAMETER OutputFile
    The path to the output ETL file.

    .PARAMETER Seconds
    The duration for the recording session in seconds.

    .OUTPUTS
    If verbose output is enabled, outputs the process ID of the WPR recording session.
    #>

    param(
        [string]$WprProfile,
        [string]$OutputFile,
        [int]$Seconds
    )

    Write-Output "Starting WPR recording for profile '$WprProfile' at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')."

    $profileExtension = if ($VerbosePreference -eq 'Continue') { ".verbose" } else { ".light" }
    $profileName = "$WprProfile$profileExtension"
    $wprArguments = "-start $profileName -filemode"

    # Start the trace and wait for 'wpr -start' to exit, so its exit code can be checked.
    $wprProcess = Start-Process wpr.exe -ArgumentList $wprArguments -WindowStyle Hidden -PassThru -Wait

    Write-Verbose "WPR process started with ID: $($wprProcess.Id)"

    # A failed start (another trace already running, not elevated) means this script owns no
    # trace, so it must not stop or cancel one.
    if ($wprProcess.ExitCode -ne 0) {
        throw "wpr $wprArguments failed with exit code $($wprProcess.ExitCode)."
    }

    # The trace is system-wide and outlives this script, so cancel it if the script is
    # stopped (Ctrl+C, a stopped pipeline) or fails before 'wpr -stop' has run.
    $stopped = $false
    try {
        # Sleep for the specified duration to allow the WPR to record.
        # This is necessary because the WPR process runs indefinitely and does not have a built-in timeout.
        Start-Sleep -Seconds $Seconds

        # Stop the WPR recording, which will complete the process and generate the ETL file.
        Invoke-Wpr -ArgumentList '-stop', $OutputFile | Out-Null
        $stopped = $true
    }
    finally {
        if (-not $stopped) {
            Invoke-Wpr -ArgumentList '-cancel' | Out-Null
        }
    }

    # Output the process information if verbose output is enabled.
    if ($wprProcess -and $wprProcess.HasExited) {
        Write-Output "WPR recording has stopped. Process Exit Code: $($wprProcess.ExitCode)"
    } else {
        Write-Output "WPR recording has stopped."
    }
    
    Write-Output "ETL file saved to $OutputFile."
}

function Invoke-WPRSensor {
    <#
    .SYNOPSIS
    The script body: records one WPR session, and logs any error to a file in OutputPath.
    #>
    [CmdletBinding()]
    param(
        [string]$Duration,
        [string]$WprProfile,
        [string]$OutputPath
    )

    # Set before anything can fail, so the error log is always named <ComputerName>_<timestamp>.log.
    $computerName = $env:COMPUTERNAME
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

    try {
        Write-Output "Script execution started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')."
        $seconds = ConvertTo-Seconds -InputDuration $Duration

        $fileName = "$computerName" + "_" + "$timestamp.etl"
        $fullPath = Join-Path -Path $OutputPath -ChildPath $fileName

        if (-not (Test-Path -Path $OutputPath)) {
            throw "Output path does not exist: $OutputPath"
        }

        InvokeWPRSession -WprProfile $WprProfile -OutputFile $fullPath -Seconds $seconds

        Write-Output "Script execution completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')."
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Error "An error occurred: $errorMessage"
        $logFile = Join-Path -Path $OutputPath -ChildPath "${computerName}_$timestamp.log"
        Add-Content -Path $logFile -Value "Error: $errorMessage"
        Write-Verbose "Error details have been logged to $logFile."
    }
}

Invoke-WPRSensor -Duration $Duration -WprProfile $WprProfile -OutputPath $OutputPath
