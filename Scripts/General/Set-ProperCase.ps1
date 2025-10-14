function Set-ProperCase {
    Param (
        [parameter(Mandatory=$true,
        ValueFromPipeline=$true)]
        $InputString
        )
    Add-Type -AssemblyName Microsoft.VisualBasic
    $OutputString = [Microsoft.VisualBasic.Strings]::StrConv($InputString,'ProperCase')
    
    return $OutputString
}