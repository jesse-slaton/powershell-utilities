function Get-LastShadowCopyDate {
    <#
    .SYNOPSIS
        Returns the creation date of the newest Volume Shadow Copy on the local computer.

    .DESCRIPTION
        Reads Win32_ShadowCopy and returns the newest InstallDate as a string in the form
        "ddd, dd MMM yyyy HH:mm zzz" with the colon removed from the UTC offset (for example
        "Thu, 05 Nov 2026 14:30 -0800"). Day and month names follow the current culture.
        Read-only.

        With no shadow copies it returns nothing and writes a verbose message. A failed CIM
        query (for example access denied) is a terminating error, not an empty result.

        Formerly Scripts/Backup/GetLastVSSSnapDate.ps1. The query now runs in the current
        process instead of through Invoke-Command -ComputerName ., so WinRM is not needed and
        it runs in the PowerShell edition that calls it.

    .EXAMPLE
        Get-LastShadowCopyDate

        Thu, 05 Nov 2026 14:30 -0800

    .EXAMPLE
        if (Test-ShadowCopy) { Get-LastShadowCopyDate } else { 'none' }

        Prints the newest shadow copy date, or "none" when there are no shadow copies.

    .NOTES
        Windows only. Reading Win32_ShadowCopy normally requires administrator rights. Runs on
        Windows PowerShell 5.1 and PowerShell 7, from 64-bit or 32-bit PowerShell: on 64-bit
        Windows a 32-bit caller is answered through the 64-bit shadow copy provider. Part of
        the StorageHealth module.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $newest = @(Get-ShadowCimInstance -ClassName Win32_ShadowCopy |
            Where-Object { $_.InstallDate } |
            Sort-Object -Property InstallDate -Descending) | Select-Object -First 1
    if (-not $newest) {
        Write-Verbose -Message 'No shadow copies found.'
        return
    }

    (Get-Date -Date $newest.InstallDate -Format 'ddd, dd MMM yyyy HH:mm zzz') -replace '([+-]\d{2}):(\d{2})$', '$1$2'
}
