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