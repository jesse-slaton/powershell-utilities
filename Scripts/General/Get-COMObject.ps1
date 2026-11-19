<#
.SYNOPSIS
    Defines Get-ComObject and stores the list of registered COM ProgIDs in $ComObjects.

.DESCRIPTION
    Defines the Get-ComObject function, which reads HKLM:\Software\Classes and returns
    the ProgIDs (names of the form Word.Application) that have a CLSID subkey, either
    all of them (-ListAll) or those matching a -like wildcard (-Filter). The script then
    runs Get-ComObject -ListAll and assigns the result to $ComObjects. It writes nothing
    to the output. Run normally, the function and $ComObjects are discarded when the
    script ends, so dot-source it to use them. Read-only.

.EXAMPLE
    . .\Get-COMObject.ps1
    $ComObjects.Count

    Dot-sources the script, then shows how many ProgIDs were found.

.EXAMPLE
    . .\Get-COMObject.ps1
    Get-ComObject -Filter 'WScript.*'

    Dot-sources the script, then lists the ProgIDs that start with "WScript.".

.NOTES
    Windows only. No admin rights needed (HKLM:\Software\Classes is readable by all
    users). Works in Windows PowerShell 5.1 and PowerShell 7.
#>


function Get-ComObject {
 
    <#
    .SYNOPSIS
        Lists COM ProgIDs registered under HKLM:\Software\Classes.

    .DESCRIPTION
        Returns the names of keys under HKLM:\Software\Classes that look like a ProgID
        (two word-character parts joined by a dot, such as Word.Application) and have a
        CLSID subkey. Version-suffixed ProgIDs with more than one dot are not included.
        Outputs strings. Read-only.

    .PARAMETER Filter
        Wildcard pattern (matched with -like) that the ProgID must match, for example
        'Excel.*'. A pattern without wildcards must match the whole ProgID.

    .PARAMETER ListAll
        Returns every ProgID found, without filtering.

    .EXAMPLE
        Get-ComObject -ListAll

        Lists every matching ProgID on the computer.

    .EXAMPLE
        Get-ComObject -Filter 'Shell.*'

        Lists ProgIDs that start with "Shell.".
    #>
    param(
        [Parameter(Mandatory=$true,
        ParameterSetName='FilterByName')]
        [string]$Filter,
 
        [Parameter(Mandatory=$true,
        ParameterSetName='ListAllComObjects')]
        [switch]$ListAll
    )
 
    $ListofObjects = Get-ChildItem HKLM:\Software\Classes -ErrorAction SilentlyContinue | Where-Object {
        $_.PSChildName -match '^\w+\.\w+$' -and (Test-Path -Path "$($_.PSPath)\CLSID")
    } | Select-Object -ExpandProperty PSChildName
 
    if ($Filter) {
        $ListofObjects | Where-Object {$_ -like $Filter}
    } else {
        $ListofObjects
    }
}

$ComObjects = @(Get-ComObject -ListAll)