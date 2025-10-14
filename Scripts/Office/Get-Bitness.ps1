
function Get-Bitness {
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