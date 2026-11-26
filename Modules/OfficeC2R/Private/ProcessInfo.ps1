# Wraps the process facts OfficeC2R reads, so tests can mock them and cover every branch
# on a single 64-bit test host.

function Get-OfficeC2RPointerSize {
    <#
    .SYNOPSIS
        Returns the pointer size of the current process in bytes.

    .DESCRIPTION
        Returns [IntPtr]::Size: 4 in a 32-bit process, 8 in a 64-bit process. Read-only.
        Private to OfficeC2R.

    .EXAMPLE
        Get-OfficeC2RPointerSize

    .NOTES
        None.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param()

    [IntPtr]::Size
}
