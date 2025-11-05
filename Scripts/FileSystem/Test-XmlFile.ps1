<#
.SYNOPSIS
    Tests whether a file contains valid XML content.

.DESCRIPTION
    This function validates that a file contains well-formed XML by using the Read-XmlFile
    function to parse its contents. Returns $true if the file is valid XML, $false otherwise.
    Supports pipeline input for processing multiple files at once.

.PARAMETER Path
    The path to the XML file(s) to test. Supports multiple paths and pipeline input.
    Accepts both FullName property from file objects and direct path strings.

.EXAMPLE
    Test-XmlFile -Path "C:\config.xml"
    Tests if config.xml contains valid XML content.

.EXAMPLE
    Get-ChildItem "C:\configs\*.xml" | Test-XmlFile
    Tests all XML files in the configs directory using pipeline input.

.EXAMPLE
    Test-XmlFile -Path "C:\data\settings.xml" -Verbose
    Tests the file with verbose output showing validation details.

.NOTES
    Author: System Administrator
    Purpose: XML file validation
    Returns: Boolean ($true for valid XML, $false for invalid)
    Dependencies: Read-XmlFile function

.LINK
    Read-XmlFile
    Test-JsonFile
#>
function Test-XmlFile {
    [cmdletbinding()]
    param (
        [alias('FullName')]
        [parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true)]
        [string[]]$Path
    )
    begin {}
    process {
        foreach ($File in $Path) {
            if (Test-Path $File) {
                $XmlFile = Read-XmlFile $File
                if ($XmlFile) {
                    Write-Verbose "$File is a valid xml file"
                    Write-Output $true
                }
                else {
                    Write-Verbose "$File is not a valid xml file"
                    Write-Output $false
                }
            }
            else {
                Write-Warning "$File does not exist"
            }
        }
    }
    end {}
}