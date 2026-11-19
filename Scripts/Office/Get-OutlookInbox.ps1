<#
.SYNOPSIS
    Defines Search-Office2016, which searches indexed Outlook items through Windows Search.

.DESCRIPTION
    Running the script only defines the Search-Office2016 function; it searches nothing
    and writes no output. Dot-source the script, then call the function.

    Search-Office2016 -Keyword <text> [-Store <store>] queries the Windows Search index
    through the Search.CollatorDSO OLE DB provider for items that CONTAIN the keyword in
    the given search store (default mapi16). It
    outputs objects with Store, DateReceived, Subject, FromAddress, FromName and Content
    (the indexed auto-summary). Read-only. See Get-Help Search-Office2016 -Full after
    dot-sourcing.

.EXAMPLE
    . .\Get-OutlookInbox.ps1
    Search-Office2016 -Keyword 'invoice'

    Searches the indexed Outlook mail of the current user for "invoice".

.EXAMPLE
    . .\Get-OutlookInbox.ps1
    Search-Office2016 -Keyword 'invoice' -Store 'mapi15' -Verbose

    Searches the mapi15 store instead of the default and shows the query and the
    result count.

.NOTES
    Requires the Windows Search service with Outlook items indexed, run as the user whose
    mailbox is indexed. Uses System.Data.OleDb, which is part of .NET Framework; written
    for Windows PowerShell 5.1.
#>


function Search-Office2016 {
    <#
    .SYNOPSIS
        Searches indexed Outlook items through the Windows Search index.

    .DESCRIPTION
        Builds a Windows Search SQL query for items in the given search store that CONTAIN the
        keyword, runs it through the Search.CollatorDSO OLE DB provider, and outputs objects
        with Store, DateReceived, Subject, FromAddress, FromName and Content (the indexed
        auto-summary). The keyword is inserted into the query as-is, so a keyword with a
        single quote breaks the query. Read-only.

        The data adapter's Fill method is called twice into the same DataSet (once for the
        verbose count and once in the if test), so results can be returned twice.

    .PARAMETER Keyword
        Text to search for, used in a CONTAINS('<Keyword>') condition. Required.

    .PARAMETER Store
        Windows Search store to search (System.Search.Store). Defaults to mapi16.

    .EXAMPLE
        Search-Office2016 -Keyword 'invoice'

        Searches the indexed Outlook mail of the current user for "invoice".

    .EXAMPLE
        Search-Office2016 -Keyword 'invoice' -Store 'mapi15' -Verbose

        Searches the mapi15 store instead of the default and shows the query and the
        result count.

    .NOTES
        Requires the Windows Search service with Outlook items indexed. Uses
        System.Data.OleDb (.NET Framework); written for Windows PowerShell 5.1.
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [string] $Keyword,
        # Change this according to your Outlook version
        [string] $Store = 'mapi16'
    )

    $provider = 'provider=Search.CollatorDSO.1;Extended Properties="Application=Windows"'

    $query = "SELECT System.Search.Store, System.Message.DateReceived, System.ItemName, System.Message.FromAddress, System.Message.FromName, System.Search.AutoSummary FROM SystemIndex WHERE CONTAINS('$Keyword') AND System.Search.Store = '$Store'"
    Write-Verbose "Searching using query: $query"

    $adapter = [System.Data.OleDb.OleDbDataAdapter]::new($query, $provider)

    $ds = New-Object System.Data.DataSet

    $count = $adapter.Fill($ds)
    Write-Verbose "Found $count results"

    if($adapter.Fill($ds) -gt 0) {
        $ds.Tables[0] | Select-Object @{
            Name = 'Store'
            Expression = {$_.'System.Search.Store'}
        },
        @{
            Name = 'DateReceived'
            Expression = {$_.'System.Message.DateReceived'}
        },
        @{
            Name = 'Subject'
            Expression = {$_.'System.ItemName'}
        },
        @{
            Name="FromAddress"
            Expression = {[string]$_.'System.Message.FromAddress'}
        },
        @{
            Name="FromName"
            Expression = {[string]$_.'System.Message.FromName'}
        },
        @{
            Name="Content"
            Expression = {$_.'System.Search.Autosummary'}
        }
    }   
}