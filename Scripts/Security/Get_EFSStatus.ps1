<#
.SYNOPSIS
    Starts cipher.exe /u /n at idle priority to scan local drives for EFS-encrypted files.

.DESCRIPTION
    Defines a PoSh.Process type that wraps the kernel32 SetPriorityClass function, then
    starts cipher.exe /u /n with standard output and standard error redirected and
    UseShellExecute off. It calls SetPriorityClass on the new process with 0x100000
    (PROCESS_MODE_BACKGROUND_BEGIN) and sets the process PriorityClass to Idle.

    The script does not wait for cipher.exe and never reads its redirected output (the
    lines that would do so are commented out), so it returns immediately and produces no
    output; the result of the scan is not captured. The return value of SetPriorityClass
    is stored in $Result and not used. cipher /u /n lists encrypted files without
    updating their keys, so no files are changed.

.EXAMPLE
    .\Get_EFSStatus.ps1

    Starts the cipher.exe scan in the background and returns without output.

.NOTES
    None. Uses only cipher.exe, which ships with Windows.
#>
$type = @" 
[DllImport("kernel32.dll", CharSet=CharSet.Auto, SetLastError=true)] 
public static extern bool SetPriorityClass(IntPtr handle, int priorityClass); 
"@ 
#public static extern bool GetPriorityClass(IntPtr handle); 
Add-Type -MemberDefinition $type -Namespace "PoSh" -Name "Process" 

$pinfo = New-Object System.Diagnostics.ProcessStartInfo
$pinfo.FileName = "cipher.exe"
$pinfo.RedirectStandardError = $true
$pinfo.RedirectStandardOutput = $true
$pinfo.UseShellExecute = $false
$pinfo.WindowStyle = "Hidden"
$pinfo.Arguments = "/u /n"
$p = New-Object System.Diagnostics.Process
$p.StartInfo = $pinfo
$p.Start() | Out-Null
$Result = [PoSh.Process]::SetPriorityClass($p.Handle, 1048576)
(Get-Process -id $p.Id).PriorityClass = 'Idle'
# $p.WaitForExit()
# $stdout = $p.StandardOutput.ReadToEnd()
# $stderr = $p.StandardError.ReadToEnd()
# Write-Host "stdout: $stdout"
# Write-Host "stderr: $stderr"
# Write-Host "exit code: " + $p.ExitCode