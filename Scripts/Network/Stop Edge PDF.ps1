<#
.SYNOPSIS
    Adds NoOpenWith and NoStaticDefaultVerb values to the .pdf file association so Edge does not take over as the PDF viewer.

.DESCRIPTION
    For each of HKCR:\.pdf, HKCR:\.pdf\OpenWithProgids and HKCR:\.pdf\OpenWithList,
    creates the NoOpenWith and NoStaticDefaultVerb values (with New-ItemProperty and no
    value) when Get-ItemProperty does not find them. Then, if the key
    HKCR:\AppXd4nrz8ff68srnhf9t5a8sbjyar1cr723_ exists, runs Set-Item on it with the
    same name. The comment says this appends an underscore to the Edge key, but Set-Item
    on a registry key sets the key's default value; it does not rename it, and the
    Test-Path checks for the name that already has the underscore.

    Writes "Stopping Edge from taking over as the default .PDF viewer" to the output
    stream, plus the objects New-ItemProperty returns. Enable Edge PDF.ps1 removes the
    values again.

.EXAMPLE
    & '.\Stop Edge PDF.ps1'

    Adds the blocking values to the .pdf association keys.

.NOTES
    Requires administrator rights (HKEY_CLASSES_ROOT). The script uses an HKCR: drive
    but does not create it; PowerShell has no HKCR: drive by default, so map one first,
    for example: New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT.
    Works in Windows PowerShell 5.1 and PowerShell 7.
#>
#Stops edge from taking over as the default .PDF viewer    
    Write-Output "Stopping Edge from taking over as the default .PDF viewer"
    $NoPDF = "HKCR:\.pdf"
    $NoProgids = "HKCR:\.pdf\OpenWithProgids"
    $NoWithList = "HKCR:\.pdf\OpenWithList" 
    If (!(Get-ItemProperty $NoPDF  NoOpenWith)) {
        New-ItemProperty $NoPDF NoOpenWith 
    }        
    If (!(Get-ItemProperty $NoPDF  NoStaticDefaultVerb)) {
        New-ItemProperty $NoPDF  NoStaticDefaultVerb 
    }        
    If (!(Get-ItemProperty $NoProgids  NoOpenWith)) {
        New-ItemProperty $NoProgids  NoOpenWith 
    }        
    If (!(Get-ItemProperty $NoProgids  NoStaticDefaultVerb)) {
        New-ItemProperty $NoProgids  NoStaticDefaultVerb 
    }        
    If (!(Get-ItemProperty $NoWithList  NoOpenWith)) {
        New-ItemProperty $NoWithList  NoOpenWith
    }        
    If (!(Get-ItemProperty $NoWithList  NoStaticDefaultVerb)) {
        New-ItemProperty $NoWithList  NoStaticDefaultVerb 
    }
            
    #Appends an underscore '_' to the Registry key for Edge
    $Edge = "HKCR:\AppXd4nrz8ff68srnhf9t5a8sbjyar1cr723_"
    If (Test-Path $Edge) {
        Set-Item $Edge AppXd4nrz8ff68srnhf9t5a8sbjyar1cr723_ 
    }
