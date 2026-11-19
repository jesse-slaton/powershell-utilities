<#
.SYNOPSIS
    Reports which wired (802.3) Group Policy objects apply to this computer to the Altiris Notification Server as custom inventory.

.DESCRIPTION
    Reads the primary user from the Altiris agent's latest basic inventory (the
    "AeX AC Primary User" data class), then uses the Group Policy Management COM object
    (GPMgmt.GPM) to run an RSoP logging-mode query for the local computer with user
    results turned off and produce an XML report.

    From the computer results it keeps the GPOs whose ExtensionName matches
    "802.3 Group Policy" and collects, for each, the GPO name and whether it is
    Enabled, IsValid, FilterAllowed and AccessDenied.

    It adds one row to the custom data class whose GUID is set in $DataClassGuid,
    with those five values in fields 0 to 4 and the script version string ($Ver) in
    field 5, and sends it to the Notification Server with SendQueued. When several
    GPOs match, each field holds the values of all of them joined by spaces. Produces
    no console output.

.EXAMPLE
    .\RSoP-WiredLANPolicy.ps1

    Run by the Altiris agent as a custom inventory task; sends the 802.3 GPO results
    to the Notification Server.

.NOTES
    Requires the Altiris (Symantec Management) agent (Altiris.AeXNSEvent and
    Altiris.BasicInventory COM objects), a custom data class matching $DataClassGuid
    on the Notification Server, and the Group Policy Management Console (GPMgmt.GPM).
    Run as SYSTEM or an administrator. Windows only (COM); written for Windows
    PowerShell 5.1.
#>
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