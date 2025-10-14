
function Read-XmlFile {
    [CmdletBinding()]
    param(
        [string]$Path
    )
    if (Test-Path $Path) {
        Write-Verbose "Found file at $Path"
        try {
            [xml]$XmlFile = Get-Content $Path -ErrorAction Stop
            $XmlFile
        }
        catch {
            Write-Warning "$Path is not a valid XML file."
        }
        
    }
    else {
        Write-Warning "$Path not found"
    }
}