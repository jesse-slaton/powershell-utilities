<#
.SYNOPSIS
    Runs BitlockerProtection.exe and appends its output, with a timestamp, to BitlockerStatus.csv.

.DESCRIPTION
    Starts .\BitlockerProtection.exe with standard output and standard error redirected,
    waits for it to exit, and reads both streams (trimmed). It then appends one row with
    Status (the standard output text) and Date (the start time, format
    "yyyy-MM-dd HH:mm tt") to .\BitlockerStatus.csv, creating the file if needed
    (Export-Csv -Append -Force -NoTypeInformation).

    If any step of starting and reading the program throws (for example when
    BitlockerProtection.exe is missing), the script writes an error and then writes the
    captured standard error with -ErrorAction Stop, which ends the script. Terminating
    errors from Export-Csv are caught and ignored. The exit code of the program is not
    checked, and the script writes nothing to the pipeline.

.EXAMPLE
    Set-Location 'C:\Tools\Bitlocker'; .\GetBitlockerProtectionStatus.ps1

    Runs C:\Tools\Bitlocker\BitlockerProtection.exe and appends its output to
    C:\Tools\Bitlocker\BitlockerStatus.csv.

.NOTES
    Requires BitlockerProtection.exe, which is not part of this repository, in the
    current directory, and write access to the current directory. Any rights the
    program itself needs (BitLocker status is usually read as administrator) apply.
#>
$ExecutionCSV = ".\BitlockerStatus.csv"
$StartTime = Get-Date -format "yyyy-MM-dd HH:mm tt"
Try {
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = ".\BitlockerProtection.exe"
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null
    $p.WaitForExit()
    $stdout = $p.StandardOutput.ReadToEnd().Trim()
    $stderr = $p.StandardError.ReadToEnd().Trim()

}
Catch {
    Write-Error "Could not get status.  Error $p.Exitcode"
    Write-Error "$stderr" -ErrorAction Stop
}

Try {
    $Status = [PSCustomObject]@{
        Status = $stdout
        Date = $StartTime
    }
    $Status | Export-CSV -Path  $ExecutionCSV -Append -Force -NoTypeInformation
}
Catch {}