<#
.SYNOPSIS
    Defines Get-Bitness, which reports whether the current PowerShell process is 32-bit or 64-bit.

.DESCRIPTION
    Running the script only defines the Get-Bitness function; it writes no output.
    Dot-source the script, then call the function.

    Get-Bitness checks [IntPtr]::Size and outputs 'x86' when it is 4, 'x64' when it is 8,
    and 'Unknown' otherwise. This is the bitness of the running PowerShell process, not
    of the operating system: 32-bit PowerShell on 64-bit Windows reports 'x86'.
    Read-only. Get-ProcessBitness-Sensor.ps1 calls this function.

.EXAMPLE
    . .\Get-Bitness.ps1
    Get-Bitness

    x64

.NOTES
    None.
#>



function Get-Bitness {
    <#
    .SYNOPSIS
        Reports whether the current PowerShell process is 32-bit or 64-bit.

    .DESCRIPTION
        Outputs 'x86' when [IntPtr]::Size is 4, 'x64' when it is 8, and 'Unknown' otherwise.
        This is the bitness of the PowerShell process, not of the operating system.

    .EXAMPLE
        Get-Bitness

        x64

    .NOTES
        None.
    #>
    [CmdletBinding()]
    param()
    if ( [IntPtr]::Size -eq 4  ) {
        Write-Output 'x86'
    }
    elseif ([IntPtr]::Size -eq 8) {
        Write-output 'x64'
    }
    else {
        Write-output 'Unknown'
    }
}