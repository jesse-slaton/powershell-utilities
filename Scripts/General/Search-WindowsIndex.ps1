Function Search-WindowsIndex {
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