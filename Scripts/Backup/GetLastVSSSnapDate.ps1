<#
.SYNOPSIS
    Returns the creation date of the newest Volume Shadow Copy on the local computer.

.DESCRIPTION
    Reads Win32_ShadowCopy and outputs the newest InstallDate as a string in the form
    "ddd, dd MMM yyyy HH:mm zzz" with the colon removed from the UTC offset
    (for example "Thu, 05 Nov 2026 14:30 -0800"). Read-only. With no shadow copies,
    Get-Date receives no date, so the output is an error or not meaningful; check
    GetVSSHasSnapshot.ps1 first.

.EXAMPLE
    .\GetLastVSSSnapDate.ps1

    Thu, 05 Nov 2026 14:30 -0800

.NOTES
    Runs its query through Invoke-Command -ComputerName ., which needs PowerShell
    remoting (WinRM) enabled on the local computer. Reading Win32_ShadowCopy normally
    requires administrator rights.
#>
Invoke-Command -ScriptBlock {

    $LastSnap = Get-CimInstance -ClassName Win32_ShadowCopy -ErrorAction SilentlyContinue | Select-Object InstallDate | Sort-Object -Property InstallDate -Descending | Select-Object -First 1
    $Date = (Get-Date -f "ddd, dd MMM yyyy HH:mm zzz" $LastSnap.InstallDate) -replace '(.*)(\+|\-)([0-9][0-9]):([0-9][0-9])', '$1$2$3$4'
    Write-Output $Date
    
} -ComputerName .