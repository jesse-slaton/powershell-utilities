<#
.SYNOPSIS
    Unfinished wrapper meant to run the Citrix Receiver Clean-Up Utility depending on UAC state.

.DESCRIPTION
    Reads EnableLUA under HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System
    (whether User Account Control is enabled). The branch for EnableLUA = 1 is empty, so
    the script currently makes no changes and produces no output.

.EXAMPLE
    .\RecieverCleanupUtilityWrapper.ps1

    Reads the UAC setting and does nothing else.

.NOTES
    No prerequisites while the script is unfinished. Reading the key does not need admin
    rights.
#>
$LUAKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$EnableLUA = Get-ItemProperty -Path $LUAKey -Name EnableLUA
If (1 -eq $EnableLUA.EnableLUA) {
    
}