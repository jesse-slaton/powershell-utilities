<#
.SYNOPSIS
    Reports whether the local computer has at least one Volume Shadow Copy.

.DESCRIPTION
    Counts Win32_ShadowCopy instances and outputs True when there is at least one,
    otherwise False. Read-only.

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