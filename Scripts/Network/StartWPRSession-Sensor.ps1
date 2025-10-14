<#
.SYNOPSIS
Starts a Windows Performance Recorder (WPR) session.

.DESCRIPTION
Initiates a WPR session for a given duration and profile. The output is an ETL file with a unique name based on the computer and timestamp.

.PARAMETER Duration
Specifies the duration in a human-friendly format (e.g., '1m', '1h', '300s'). Default is '5m'.

.PARAMETER WprProfile
Specifies the WPR profile to record from a predefined set of valid profiles. Default is 'GeneralProfile'.

.PARAMETER OutputPath
Specifies the output path for the ETL file. Default is the user's Desktop.

.PARAMETER Verbose
Enables verbose output.

.EXAMPLE
.\StartWPRSession.ps1 -Duration "30m" -WprProfile "CPU" -OutputPath "C:\ETLs" -Verbose

This example starts a 30-minute recording session using the CPU profile, saves the ETL to C:\ETLs, and outputs verbose logs.

.NOTES
For more information on Windows Performance Recorder, see the following:
https://docs.microsoft.com/en-us/windows-hardware/test/wpt/windows-performance-recorder

.LINK
https://docs.microsoft.com/en-us/windows-hardware/test/wpt/windows-performance-recorder

#>
param(
    [string]$Duration = "5m",
    [ValidateSet("GeneralProfile", "CPU", "DiskIO", "FileIO", "Registry", "Network", "Heap", "Pool", "VirtualAllocation", "Audio", "Video", "Power", "InternetExplorer", "EdgeBrowser", "Minifilter", "GPU", "Handle", "XAMLActivity", "HTMLActivity", "DesktopComposition", "XAMLAppResponsiveness", "HTMLResponsiveness", "ReferenceSet", "ResidentSet", "XAMLHTMLAppMemoryAnalysis", "UTC", "DotNET", "WdfTraceLoggingProvider", "HeapSnapshot")]
    [string]$WprProfile = "GeneralProfile",
    [string]$OutputPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
)

function ConvertTo-Seconds {
    param([string]$InputDuration)

    switch -Regex ($InputDuration) {
        '(\d+)h'   { return [int]$matches[1] * 3600 }
        '(\d+)m'   { return [int]$matches[1] * 60 }
        '(\d+)s'   { return [int]$matches[1] }
        default    { throw "Invalid duration format. Please specify the duration in hours (h), minutes (m), or seconds (s)." }
    }
}

function InvokeWPRSession {
    <#
    .SYNOPSIS
    Invokes a WPR recording session.

    .DESCRIPTION
    Starts a WPR recording session with the specified profile. It runs the WPR process in the background hidden from the user.
    The function uses Start-Sleep to allow the recording to proceed for the specified duration and then stops the recording.

    The Start-Sleep cmdlet is used instead of the -Wait parameter on Start-Process because the WPR process does not exit on its own after a set duration. 
    The WPR process is designed to run continuously until it is explicitly stopped with a 'wpr -stop' command. Therefore, we use Start-Sleep to pause the 
    script for the desired duration before issuing the stop command to end the recording session and produce the ETL file.

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

    # Start the WPR process, storing the process object in a variable for later use.
    $wprProcess = Start-Process wpr.exe -ArgumentList $wprArguments -WindowStyle Hidden -PassThru

    Write-Verbose "WPR process started with ID: $($wprProcess.Id)"

    # Sleep for the specified duration to allow the WPR to record. 
    # This is necessary because the WPR process runs indefinitely and does not have a built-in timeout.
    Start-Sleep -Seconds $Seconds

    # Stop the WPR recording, which will complete the process and generate the ETL file.
    wpr -stop $OutputFile | Out-Null

    # Output the process information if verbose output is enabled.
    if ($wprProcess -and $wprProcess.HasExited) {
        Write-Output "WPR recording has stopped. Process Exit Code: $($wprProcess.ExitCode)"
    } else {
        Write-Output "WPR recording has stopped."
    }
    
    Write-Output "ETL file saved to $OutputFile."
}

# Script body
try {
    Write-Output "Script execution started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')."
    $seconds = ConvertTo-Seconds -InputDuration $Duration

    $computerName = $env:COMPUTERNAME
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
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
    $logFile = Join-Path -Path $OutputPath -ChildPath "$computerName_$timestamp.log"
    Add-Content -Path $logFile -Value "Error: $errorMessage"
    Write-Verbose "Error details have been logged to $logFile."
}
