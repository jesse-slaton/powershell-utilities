<#
.SYNOPSIS
    Removes the NoOpenWith and NoStaticDefaultVerb values that Stop Edge PDF.ps1 adds to the .pdf file association.

.DESCRIPTION
    For each of HKCR:\.pdf, HKCR:\.pdf\OpenWithProgids and HKCR:\.pdf\OpenWithList,
    removes the NoOpenWith and NoStaticDefaultVerb values when Get-ItemProperty finds
    them. Then, if the key HKCR:\AppXd4nrz8ff68srnhf9t5a8sbjyar1cr723_ exists, runs
    Set-Item on it with the name without the trailing underscore. The comment says this
    renames the Edge key, but Set-Item on a registry key sets the key's default value;
    it does not rename it.

    Writes "Setting Edge back to default" to the output stream.

.EXAMPLE
    & '.\Enable Edge PDF.ps1'

    Reverses the .pdf association changes made by Stop Edge PDF.ps1.

.NOTES
    Requires administrator rights (HKEY_CLASSES_ROOT). The script uses an HKCR: drive
    but does not create it; PowerShell has no HKCR: drive by default, so map one first,
    for example: New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT.
    Works in Windows PowerShell 5.1 and PowerShell 7.
#>
Write-Output "Setting Edge back to default"
    $NoPDF = "HKCR:\.pdf"
    $NoProgids = "HKCR:\.pdf\OpenWithProgids"
    $NoWithList = "HKCR:\.pdf\OpenWithList"
    #Sets edge back to default
    If (Get-ItemProperty $NoPDF  NoOpenWith) {
        Remove-ItemProperty $NoPDF  NoOpenWith
    } 
    If (Get-ItemProperty $NoPDF  NoStaticDefaultVerb) {
        Remove-ItemProperty $NoPDF  NoStaticDefaultVerb 
    }       
    If (Get-ItemProperty $NoProgids  NoOpenWith) {
        Remove-ItemProperty $NoProgids  NoOpenWith 
    }        
    If (Get-ItemProperty $NoProgids  NoStaticDefaultVerb) {
        Remove-ItemProperty $NoProgids  NoStaticDefaultVerb 
    }        
    If (Get-ItemProperty $NoWithList  NoOpenWith) {
        Remove-ItemProperty $NoWithList  NoOpenWith
    }    
    If (Get-ItemProperty $NoWithList  NoStaticDefaultVerb) {
        Remove-ItemProperty $NoWithList  NoStaticDefaultVerb
    }
        
    #Removes an underscore '_' from the Registry key for Edge
    $Edge2 = "HKCR:\AppXd4nrz8ff68srnhf9t5a8sbjyar1cr723_"
    If (Test-Path $Edge2) {
        Set-Item $Edge2 AppXd4nrz8ff68srnhf9t5a8sbjyar1cr723
    }
