function Search-Office2016 {
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