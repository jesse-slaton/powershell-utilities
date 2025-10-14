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