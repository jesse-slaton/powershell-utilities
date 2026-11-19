<#
.SYNOPSIS
    Defines the Search-WindowsIndex function, which finds files through the Windows Search index.

.DESCRIPTION
    Defines Search-WindowsIndex and does nothing else: running the script without
    dot-sourcing it produces no output and leaves nothing defined. After the script is
    dot-sourced, Search-WindowsIndex -Pattern <Pattern> [-Path <Folder>] queries the
    Windows Search index (through the ADODB COM objects and the Search.CollatorDSO
    provider) and outputs the full path of each indexed file whose name matches the
    pattern under that folder. See Get-Help Search-WindowsIndex -Full for its
    parameters. Read-only.

.EXAMPLE
    . .\Search-WindowsIndex.ps1
    Search-WindowsIndex -Pattern '*.pdf'

    Dot-sources the script, then lists indexed PDF files under the current folder.

.EXAMPLE
    . .\Search-WindowsIndex.ps1
    Search-WindowsIndex -Path 'D:\Projects' -Pattern '*.ps1'

    Lists indexed .ps1 files under D:\Projects.

.NOTES
    Windows only. Requires the Windows Search service to be running, and only finds
    files in indexed locations. Uses the ADODB COM objects. No admin rights needed.
#>


Function Search-WindowsIndex {
    <#
    .SYNOPSIS
        Searches the Windows Search index for files by name under a folder.

    .DESCRIPTION
        Opens an ADODB connection to the Windows Search provider (Search.CollatorDSO)
        and queries SYSTEMINDEX for items whose System.FileName matches Pattern and
        whose System.ItemPathDisplay is under Path. Outputs the full path of each
        match as a string. Only indexed locations return results. Read-only.

    .PARAMETER Path
        Folder to search under, including its subfolders. Defaults to the current
        location when omitted or empty. Accepts pipeline input, but only the last
        piped value is used because the function has no process block.

    .PARAMETER Pattern
        File name pattern. Each * is turned into the SQL LIKE wildcard %, so '*.log'
        matches names ending in .log. The pattern is inserted into the query text
        as is, so a single quote in it breaks the query.

    .EXAMPLE
        Search-WindowsIndex -Pattern '*.pdf'

        Lists indexed PDF files under the current folder.

    .EXAMPLE
        Search-WindowsIndex -Path 'C:\Users\Public\Documents' -Pattern 'report*'

        Lists indexed files whose names start with "report" under that folder.
    #>
param (  
    [Parameter(ValueFromPipeline = $true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Pattern)  

    if($Path -eq ""){$Path = $PWD;} 

    $pattern = $pattern -replace "\*", "%"  
    $path = $path + "\%"

    $con = New-Object -ComObject ADODB.Connection
    $rs = New-Object -ComObject ADODB.Recordset

    $con.Open("Provider=Search.CollatorDSO;Extended Properties='Application=Windows';")
    $rs.Open("SELECT System.ItemPathDisplay FROM SYSTEMINDEX WHERE System.FileName LIKE '" + $pattern + "' AND System.ItemPathDisplay LIKE '" + $path + "'" , $con)

    While(-Not $rs.EOF){
        $rs.Fields.Item("System.ItemPathDisplay").Value
        $rs.MoveNext()
    }
}