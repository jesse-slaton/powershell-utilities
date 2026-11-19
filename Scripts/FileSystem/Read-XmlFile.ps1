<#
.SYNOPSIS
    Defines the Read-XmlFile function, which loads a file as an [xml] document.

.DESCRIPTION
    Running this script only defines the Read-XmlFile function; nothing is read and
    nothing is output. Dot-source it to use the function.

    Read-XmlFile -Path <file> reads the file with Get-Content, casts it to [xml], and
    outputs the XmlDocument. It writes a warning instead when the file does not exist
    or is not valid XML. Read-only.

.EXAMPLE
    . .\Read-XmlFile.ps1
    $config = Read-XmlFile -Path 'C:\Temp\settings.xml'

    Defines the function, then loads settings.xml into $config.

.NOTES
    None.
#>


function Read-XmlFile {
    <#
    .SYNOPSIS
        Loads a file as an [xml] document.

    .DESCRIPTION
        If Path exists, reads it with Get-Content, casts the content to [xml], and
        outputs the XmlDocument. Writes the warning "<Path> is not a valid XML file."
        if the cast fails, or "<Path> not found" if the path does not exist. Read-only.

    .PARAMETER Path
        Path of the XML file to read. Not mandatory, but an empty value makes Test-Path
        fail with a parameter binding error.

    .EXAMPLE
        Read-XmlFile -Path 'C:\Temp\settings.xml'

        Outputs the XmlDocument for settings.xml.

    .EXAMPLE
        (Read-XmlFile -Path 'C:\Temp\settings.xml' -Verbose).DocumentElement.Name

        Writes "Found file at C:\Temp\settings.xml" as verbose output, then the name of
        the root element.

    .NOTES
        None.
    #>
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