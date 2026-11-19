<#
.SYNOPSIS
    Reports whether the local computer has at least one Volume Shadow Copy.

.DESCRIPTION
    Reads Win32_ShadowCopy and outputs the result of ($snapshots.Count -gt 0): True when
    there are two or more shadow copies, False when there are none. With exactly one
    shadow copy, Get-CimInstance returns a single object rather than an array; if that
    object does not report a Count (possible on Windows PowerShell 5.1), the script
    outputs False even though a shadow copy exists. Read-only.

.EXAMPLE
    .\GetVSSHasSnapshot.ps1

    True

.NOTES
    Runs its query through Invoke-Command -ComputerName ., which needs PowerShell
    remoting (WinRM) enabled on the local computer. Reading Win32_ShadowCopy normally
    requires administrator rights.
#>
Invoke-Command -ScriptBlock {

    $HasSnap = Get-CimInstance -ClassName Win32_ShadowCopy -ErrorAction SilentlyContinue
    $Output = $HasSnap.Count -gt 0
    Write-Output $Output
    
} -ComputerName .