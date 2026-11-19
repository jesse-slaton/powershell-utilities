<#
.SYNOPSIS
    Defines Set-ProperCase, which converts a string to proper case.

.DESCRIPTION
    Defines the Set-ProperCase function and does nothing else: running the script
    without dot-sourcing it produces no output and leaves nothing defined. The
    function loads the Microsoft.VisualBasic assembly and returns its input converted
    with StrConv ProperCase. See Get-Help Set-ProperCase -Full.

.EXAMPLE
    . .\Set-ProperCase.ps1
    Set-ProperCase 'JOHN SMITH'

    Dot-sources the script, then returns "John Smith".

.NOTES
    Needs the Microsoft.VisualBasic assembly, which is loaded with Add-Type. No admin
    rights or network access needed.
#>


function Set-ProperCase {
    <#
    .SYNOPSIS
        Returns a string converted to proper case (each word capitalized, the rest lower case).

    .DESCRIPTION
        Calls [Microsoft.VisualBasic.Strings]::StrConv with the ProperCase option on
        InputString and returns the result. The input is not changed.

    .PARAMETER InputString
        Text to convert. Accepts pipeline input, but only the last piped value is
        converted because the function has no process block.

    .EXAMPLE
        Set-ProperCase -InputString 'JOHN SMITH'

        Returns "John Smith".

    .EXAMPLE
        'hello world' | Set-ProperCase

        Returns "Hello World".
    #>
    Param (
        [parameter(Mandatory=$true,
        ValueFromPipeline=$true)]
        $InputString
        )
    Add-Type -AssemblyName Microsoft.VisualBasic
    $OutputString = [Microsoft.VisualBasic.Strings]::StrConv($InputString,'ProperCase')
    
    return $OutputString
}