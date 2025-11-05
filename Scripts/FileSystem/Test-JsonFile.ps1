<#
.SYNOPSIS
    Tests whether a file contains valid JSON content.

.DESCRIPTION
    This function validates that a file contains well-formed JSON by attempting to parse
    its contents using ConvertFrom-Json. Returns $true if the file is valid JSON, $false
    otherwise. Supports pipeline input for processing multiple files at once.

.PARAMETER Path
    The path to the JSON file(s) to test. Supports multiple paths and pipeline input.
    Accepts both FullName property from file objects and direct path strings.

.EXAMPLE
    Test-JsonFile -Path "C:\config.json"
    Tests if config.json contains valid JSON content.

.EXAMPLE
    Get-ChildItem "C:\configs\*.json" | Test-JsonFile
    Tests all JSON files in the configs directory using pipeline input.

.EXAMPLE
    Test-JsonFile -Path "C:\data\settings.json" -Verbose
    Tests the file with verbose output showing validation details.

.NOTES
    Author: System Administrator
    Purpose: JSON file validation
    Returns: Boolean ($true for valid JSON, $false for invalid)

.LINK
    ConvertFrom-Json
    Test-XmlFile
#>
function Test-JsonFile {
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
                try {
                    $JsonFile = Get-Content -Path $File | ConvertFrom-Json -ErrorAction Stop
                    if ($JsonFile) {
                        Write-Verbose "$File is a valid json file"
                        Write-Output $true
                    }
                }
                catch {
                    Write-Verbose "$File is not a valid json file"
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