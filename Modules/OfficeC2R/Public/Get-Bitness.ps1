function Get-Bitness {
    <#
    .SYNOPSIS
        Reports whether the current PowerShell process is 32-bit or 64-bit.

    .DESCRIPTION
        Outputs 'x86' when [IntPtr]::Size is 4, 'x64' when it is 8, and 'Unknown' otherwise.
        This is the bitness of the running PowerShell process, not of the operating system
        or of Office: 32-bit PowerShell on 64-bit Windows reports 'x86'. Use
        Get-OfficeC2RBitness for the bitness of Office. Read-only.

        Replaces Scripts/Office/Get-Bitness.ps1, which had to be dot-sourced.

    .EXAMPLE
        Get-Bitness

        x64

    .EXAMPLE
        if ((Get-Bitness) -eq 'x86') { Write-Warning 'Running in 32-bit PowerShell' }

        Warns when the session is a 32-bit process.

    .NOTES
        None. Part of the OfficeC2R module.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    switch (Get-OfficeC2RPointerSize) {
        4 { 'x86' }
        8 { 'x64' }
        default { 'Unknown' }
    }
}
