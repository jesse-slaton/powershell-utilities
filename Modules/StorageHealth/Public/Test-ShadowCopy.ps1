function Test-ShadowCopy {
    <#
    .SYNOPSIS
        Reports whether the local computer has at least one Volume Shadow Copy.

    .DESCRIPTION
        Reads Win32_ShadowCopy and returns $true when there is at least one shadow copy and
        $false when there are none. The result is wrapped in an array before it is counted,
        so a single shadow copy reads as $true on Windows PowerShell 5.1 too. A failed CIM
        query (for example access denied) is a terminating error, not $false. Read-only.

        Formerly Scripts/Backup/GetVSSHasSnapshot.ps1. The query now runs in the current
        process instead of through Invoke-Command -ComputerName ., so WinRM is not needed and
        it runs in the PowerShell edition that calls it.

    .EXAMPLE
        Test-ShadowCopy

        True

    .EXAMPLE
        if (-not (Test-ShadowCopy)) { Write-Warning 'No restore points or shadow copies.' }

        Warns when the computer has no shadow copies.

    .NOTES
        Windows only. Reading Win32_ShadowCopy normally requires administrator rights. Runs on
        Windows PowerShell 5.1 and PowerShell 7, from 64-bit or 32-bit PowerShell: on 64-bit
        Windows a 32-bit caller is answered through the 64-bit shadow copy provider. Part of
        the StorageHealth module.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    @(Get-ShadowCimInstance -ClassName Win32_ShadowCopy).Count -gt 0
}
