#Modify this varaible with the custom data class guid
$DataClassGuid = "{f5a8dd4e-02af-43d7-b3a3-d1c8f1fd502c}"
#Script Version
$Ver = "10/22/2018 16:38:31"

$ComputerName = $Env:COMPUTERNAME
$RSOP = @()

$nse = New-Object -ComObject Altiris.AeXNSEvent
$nse.To = "{1592B913-72F3-4C36-91D2-D4EDA21D2F96}"
$nse.Priority = 1
$DCInstance = $nse.AddDataClass($DataClassGuid)
$DataClass = $nse.AddDataBlock($DCInstance)

#Query Altiris Agent's most recent basic inventory to determine the primary user account information
$BasicInventory = New-Object -ComObject Altiris.BasicInventory
[xml]$inventory = $BasicInventory.Inventory
$PrimaryUser = ($inventory.message.body.inventory.dataClass | `
        Where-Object {$_.name -eq 'AeX AC Primary User'}).data.childnodes.row

#Obtain SID for the Primary User Account
$UserName = "$($PrimaryUser.c3)\$($PrimaryUser.c2)"

$gpm = New-Object -ComObject GPMgmt.GPM
$constants = $gpm.GetConstants()
$gpmRSOP = $GPM.GetRSOP($Constants.RSOPModeLogging, $null, 0)
$gpmRSOP.LoggingComputer = $ComputerName
$gpmRSOP.LoggingUser = $UserName
#Only query Computer Policy results
$gpmRSOP.LoggingFlags = $Constants.RsopLoggingNoUser
$gpmRSOP.CreateQueryResults()
[xml]$report = ($gpmRSOP.GenerateReport($constants.ReportXML)).Result

$report.Rsop.ComputerResults.GPO | `
    Where-Object {$_.ExtensionName -match '802.3 Group Policy' } | `
    ForEach-Object {
    $RSOPData = [PSCustomObject] @{
        0 = $_.Name
        1 = [bool]($_.Enabled -eq 'true')
        2 = [bool]($_.IsValid -eq 'true')
        3 = [bool]($_.FilterAllowed -eq 'true')
        4 = [bool]($_.AccessDenied -eq 'true')
    }
    $RSOP += $RSOPData
}
#Add new row of data
$DataRow = $DataClass.AddRow()        
$DataRow.SetField(0, "$($RSOP.0)")
$DataRow.SetField(1, "$($RSOP.1)")
$DataRow.SetField(2, "$($RSOP.2)")
$DataRow.SetField(3, "$($RSOP.3)")
$DataRow.SetField(4, "$($RSOP.4)")
$DataRow.SetField(5, "$Ver")

$nse.SendQueued()