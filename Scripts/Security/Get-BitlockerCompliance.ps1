<#
.SYNOPSIS
    Builds BitLocker compliance CSV reports from the Altiris CMDB and Active Directory and opens them in Excel.

.DESCRIPTION
    Queries the Altiris CMDB SQL database for each managed computer's encryption status,
    reads computer objects from the Active Directory search roots you name and BitLocker
    recovery information under -RecoverySearchRoot, joins the three sets by computer name,
    writes four CSV reports to C:\Temp and opens them in Excel. The script makes no changes
    to SQL or Active Directory.

    The four reports, each limited to the rows named:
        VULNERABLE.csv          in AD and Altiris, not encrypted (names containing VIEW excluded)
        ENCRYPTED.csv           in AD and Altiris, 'Bitlocker: Protected' or 'Checkpoint: Enabled'
                                (names containing VIEW excluded)
        IN AD NOT ALTIRIS.csv   in AD, not in Altiris
        IN ALTIRIS NOT AD.csv   in Altiris, not in AD

    Every report has the same columns, in this order. A value of '---' means the computer was
    not found in that source; values joined with commas list one entry per recovery object.
        AD_Name                  computer name in Active Directory
        AD_Created               AD computer object creation date (yyyy/MM/dd)
        AD_Changed               AD computer object last-change date (yyyy/MM/dd)
        BL_Name                  computer name that owns the BitLocker recovery objects
        BL_Created_Date          creation timestamp of each recovery object, from its name
        BL_Key_Count             number of BitLocker recovery objects for the computer
        BL_PW_ID                 recovery password ID of each recovery object, as {GUID}; the
                                 ID only, never the recovery password itself
        ALT_Name                 computer name in the Altiris CMDB
        ALT_PC_Loc               Altiris computer location
        ALT_User_Loc             always 'DISABLED 4/1/2019' (the user location is not reported)
        ALT_Managed              Altiris managed flag
        ALT_OS_Name              operating system name in Altiris
        ALT_ENC_Stat             encryption status (Checkpoint or BitLocker state, or
                                 'No Inventory Data')
        ALT_ENC_Perc             BitLocker conversion percentage
        ALT_User_ID              Altiris user ID
        ALT_User_Name            Altiris user name
        ALT_BL_LastClientUpdate  last time the client sent BitLocker inventory to Altiris
        ALT_BL_LastInvChange     last time that BitLocker inventory changed
        ALT_LastPolicyRequest    last Altiris policy request (agent heartbeat)

.PARAMETER ServerInstance
    SQL Server that hosts the Altiris CMDB, as a host name or host\instance (for example
    'sql01.contoso.com' or 'sql01\ALTIRIS').

.PARAMETER Database
    Name of the Altiris CMDB database on ServerInstance.

.PARAMETER ComputerSearchRoot
    One or more Active Directory containers to read computer objects from, as distinguished
    names (for example 'OU=Computers,DC=contoso,DC=com') or LDAP:// paths. Results from all
    of them are combined, and a computer found under more than one root (overlapping roots,
    such as an OU and one of its child OUs) is listed once.

.PARAMETER RecoverySearchRoot
    Active Directory container to search for msFVE-RecoveryInformation objects, usually the
    domain root (for example 'DC=contoso,DC=com'), as a distinguished name or LDAP:// path.

.PARAMETER Credential
    SQL Server login to connect with. When omitted, the script connects with Windows
    integrated security as the current user. The password is passed to SQL Server as a
    read-only SecureString (SqlCredential); it is never stored in the script or written into
    the connection string.

.PARAMETER ConnectionTimeout
    Seconds to wait for the SQL connection to open. Defaults to 30.

.EXAMPLE
    .\Get-BitlockerCompliance.ps1 -ServerInstance 'sql01.contoso.com' -Database 'CMDB' -ComputerSearchRoot 'OU=Computers,DC=contoso,DC=com' -RecoverySearchRoot 'DC=contoso,DC=com'

    Connects to SQL Server with Windows integrated security and builds the reports.

.EXAMPLE
    $SqlLogin = Get-Credential -Message 'Altiris CMDB SQL login'
    .\Get-BitlockerCompliance.ps1 -ServerInstance 'sql01.contoso.com' -Database 'CMDB' -ComputerSearchRoot 'OU=Computers,DC=contoso,DC=com', 'OU=Laptops,DC=contoso,DC=com' -RecoverySearchRoot 'DC=contoso,DC=com' -Credential $SqlLogin

    Connects with a SQL Server login and reads computers from two OUs.

.NOTES
    Requires Windows with Microsoft Excel installed (COM), network access to the SQL server,
    and a domain account that may read computer objects and BitLocker recovery information
    in Active Directory. -Credential must be a SQL Server login; for a Windows account, run
    the script as that account and omit -Credential.

    If the SQL query or an Active Directory search fails, the script writes an error and
    exits with code 1 before it writes or opens any report.

    The script deliberately never reads BitLocker recovery passwords from Active Directory,
    only their IDs, so its CSVs cannot contain a recovery key.
#>
[CmdletBinding()]
param(
    # SQL Server host or host\instance that holds the Altiris CMDB.
    [Parameter(Mandatory)]
    [string]$ServerInstance,

    # Altiris CMDB database name.
    [Parameter(Mandatory)]
    [string]$Database,

    # AD containers (DN or LDAP:// path) to read computer objects from.
    [Parameter(Mandatory)]
    [string[]]$ComputerSearchRoot,

    # AD container (DN or LDAP:// path) to search for BitLocker recovery information.
    [Parameter(Mandatory)]
    [string]$RecoverySearchRoot,

    # SQL Server login. Omit to use Windows integrated security. Not stored in this script.
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential = [System.Management.Automation.PSCredential]::Empty,

    [ValidateRange(1, 3600)]
    [int]$ConnectionTimeout = 30
)

#Returns an unopened SqlConnection. With a credential, the login travels as a SqlCredential
#(read-only SecureString) and never appears in the connection string; without one, the
#connection uses Windows integrated security.
function New-ComplianceSqlConnection {
    param (
        [Parameter(Mandatory)]
        [string]$ServerInstance,

        [Parameter(Mandatory)]
        [string]$Database,

        [int]$ConnectionTimeout = 30,

        [System.Management.Automation.PSCredential]
        $Credential = [System.Management.Automation.PSCredential]::Empty
    )
    $Builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $Builder['Data Source'] = $ServerInstance
    $Builder['Initial Catalog'] = $Database
    $Builder['Connect Timeout'] = $ConnectionTimeout

    if ($null -ne $Credential -and $Credential -ne [System.Management.Automation.PSCredential]::Empty) {
        $Password = $Credential.Password.Copy()
        $Password.MakeReadOnly()
        $SqlCredential = New-Object System.Data.SqlClient.SqlCredential -ArgumentList $Credential.UserName, $Password
        New-Object System.Data.SqlClient.SqlConnection -ArgumentList $Builder.ConnectionString, $SqlCredential
    }
    else {
        $Builder['Integrated Security'] = $true
        New-Object System.Data.SqlClient.SqlConnection -ArgumentList $Builder.ConnectionString
    }
}

#Opens the connection, runs the query and returns the filled DataSet. The connection is
#always disposed, and any failure is rethrown so the caller can stop before it writes a
#report (an empty result set would otherwise read as a clean report).
function Invoke-ComplianceQuery {
    param (
        [Parameter(Mandatory)]
        $Connection,

        [Parameter(Mandatory)]
        [string]$Query,

        [int]$CommandTimeout = 120
    )
    try {
        $Connection.Open()
        $Command = $Connection.CreateCommand()
        $Command.CommandText = $Query
        $Command.CommandTimeout = $CommandTimeout
        $DataSet = New-Object System.Data.DataSet
        $Adapter = New-Object System.Data.SqlClient.SqlDataAdapter -ArgumentList $Command
        [void]$Adapter.Fill($DataSet)
        $DataSet
    }
    catch {
        throw
    }
    finally {
        $Connection.Dispose()
    }
}

#Accepts a distinguished name or an LDAP:// (or GC://) path and returns an ADSI path.
#Surrounding whitespace is trimmed and the provider prefix is upper-cased, because ADSI
#provider names are case-sensitive ('ldap://' fails where 'LDAP://' works).
function ConvertTo-LdapPath {
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )
    $Path = $Path.Trim()
    if ($Path -match '^(?<Provider>LDAP|GC)://(?<Rest>.*)$') {
        '{0}://{1}' -f $Matches['Provider'].ToUpperInvariant(), $Matches['Rest']
    }
    else {
        "LDAP://$Path"
    }
}

#Returns a DirectorySearcher for one AD search root. Kept separate so tests can stand in
#for ADSI.
function New-ComplianceAdSearcher {
    param (
        [Parameter(Mandatory)]
        [string]$Filter,

        [Parameter(Mandatory)]
        [string[]]$Property,

        [Parameter(Mandatory)]
        [string]$SearchRoot
    )
    $Searcher = [adsisearcher]$Filter
    $Searcher.PropertiesToLoad.AddRange($Property)
    $Searcher.SearchRoot = ConvertTo-LdapPath -Path $SearchRoot
    $Searcher.PageSize = 200
    $Searcher
}

#Runs one AD search and returns its results. Any ADSI failure (bad path, no access) is
#rethrown with the search root named, so the caller can stop instead of reporting a partial
#or empty AD set. @() enumerates inside the try because ADSI raises some errors only while
#the results are read.
function Invoke-ComplianceAdSearch {
    param (
        [Parameter(Mandatory)]
        [string]$Filter,

        [Parameter(Mandatory)]
        [string[]]$Property,

        [Parameter(Mandatory)]
        [string]$SearchRoot
    )
    try {
        $Searcher = New-ComplianceAdSearcher -Filter $Filter -Property $Property -SearchRoot $SearchRoot
        $Results = @($Searcher.FindAll())
    }
    catch {
        throw "AD search of '$SearchRoot' failed: $($_.Exception.Message)"
    }
    $Results
}

#Reads computer objects from every search root and returns one row per computer name, so
#overlapping roots (a parent OU and one of its children) do not list a computer twice.
function Get-ComplianceAdComputer {
    param (
        [Parameter(Mandatory)]
        [string[]]$SearchRoot
    )
    $ADTMP = @()
    FOREACH ($Root IN $SearchRoot){
        $Computers = $null
        $Computers = @(Invoke-ComplianceAdSearch -Filter '(ObjectCategory=Computer)' -Property 'name','whencreated','whenchanged' -SearchRoot $Root)

        FOREACH ($ITEM IN $Computers){
            [STRING]$ADNAME = $ITEM.Properties.name
            $WCR = $ITEM.Properties.whencreated.ToLongDateString()
                $WCR = "{0:yyyy/MM/dd}" -f [datetime]$WCR
            $WCH = $ITEM.Properties.whenchanged.ToLongDateString()
                $WCH = "{0:yyyy/MM/dd}" -f [datetime]$WCH

            $ITEMTMP = New-Object PSObject -Property @{
                AD_Name     = $ADNAME
                AD_Created  = $WCR
                AD_Changed  = $WCH
            }
            $ADTMP += $ITEMTMP
        }
    }
    $ADTMP | Sort-Object -Property AD_Name -Unique | Select-Object -Property AD_Name,AD_Created,AD_Changed
}

CLS

$elapsed = [System.Diagnostics.Stopwatch]::StartNew()
    write-host "Started at $(get-date)"
    write-host ""
    write-host ""

Write-Host "Starting PreScript Tasks..."
#REGION FUNCTIONS
#Get-Status updates screen with elapsed time
#EXAMPLE:  [Get-Status "REPORT:  Altiris BL Master  " "Total time elapsed:  "]
function Get-Status {
    param (
       $MSG1 `
        ,$MSG2
    )
    write-host "$MSG1 $(get-date)"
    write-host "$MSG2 $($elapsed.Elapsed.ToString())"    
    Write-Host ""
}
#ENDREGION FUNCTIONS
Get-Status "     Tasks Complete  " "          Total Time Elapsed:  "

Write-Host "Starting SQL Query..."
#REGION SQL QUERY
#CONFIG: ServerInstance, Database, Credential and ConnectionTimeout are script parameters

#NEW QUERY TO PULL MASTER REF DATA FOR BL
$Query = @" 
    

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED 

-- SELECT CLAUSE 
SELECT DISTINCT 
    vc.NAME                     AS 'Computer Name'  
    , cl.Location               AS 'Computer Location'  
    , vc.[OS Name]              AS 'OS Name'
    , vc.[User]                 AS 'User ID'  
    , vu.[Display Name]         AS 'User Name'  
    --, ul.[Friendly Location]    AS 'User Location'  
    , vc.IsManaged              AS 'Managed'  
    
    -- ###CHECK LOGIC - ENCRYPT LOGIC 
    , 'Encryption Status' = CASE  
        WHEN cpe._ResourceGuid IS NOT NULL  
            THEN 'Checkpoint: Enabled'  
        WHEN cpe._ResourceGuid IS NULL AND LEFT(vc.[OS Name], 5) = 'Micro'  
            THEN 'Checkpoint: Not Encrypted'  
        WHEN bl.EncryptionStatus IS NOT NULL 
            THEN 'Bitlocker: ' + bl.EncryptionStatus 
        WHEN cpe._ResourceGuid IS NULL AND bl.EncryptionStatus IS NULL 
            THEN 'No Inventory Data' 
    END 
    , bl.ConvertPercentage        AS 'ConvertPercentage' 
    
    -- ORIGINAL BL INV CREATED DATE 
    --, rg.CreatedDate            AS 'BL_First' 
    
    -- LAST TIME CLIENT SENT DATA TO ALTIRIS 
    , rg.ModifiedDate           AS 'BL_LastClientUpdate' 
    
    -- LAST TIME INVENTORY ACTUALLY CHANGED 
    -- E.G. DATECODE, ENCRYPTION STATUS 
    , rg.DataLastChangedDate    AS 'BL_LastInvChange' 

        -- LAST POLICY REQUEST (E.G. ALTIRIS HEARTBEAT) 
    , cs.LastPolicyRequest AS 'ALT_LastPolicyRequest' 


-- FROM CLAUSE 
FROM  
    --PRIMARY TABLE (VCOMPUTER EX?) 
    vComputerEx vc 

    -- CL (Computer Location) 
    LEFT JOIN v_MIG_Computer_Location cl  
        ON cl.ParentResourceGuid = vc.[Guid]  

    -- VU (User Name) 
    LEFT JOIN vUser vu  
        ON vu.NAME = vc.[User] AND  
        LEN(vu.[Name]) > 0 

    -- BL (Bitlocker Inventory) 
    LEFT JOIN Inv_Bitlocker bl  
        ON bl._ResourceGuid = vc.[Guid] 

    -- RUS|RG (Bitlocker Inventory Dates) 
    LEFT JOIN ( 
        SELECT * 
        FROM ResourceUpdateSummary rus 
        WHERE rus.InventoryClassGuid = 'f504be78-e609-42cc-b600-d3e0daba1a29'        
    ) AS RG 
        ON RG.ResourceGuid = vc.[Guid] 
    
    -- ###CHECK LOGIC - VSC|IIS|CPE (Checkpoint) 
    LEFT JOIN (  
        SELECT DISTINCT iis._resourceguid 
        FROM inv_installedsoftware iis 
        INNER JOIN vSoftwareComponent vsc 
            ON vsc.Guid = iis._SoftwareComponentGuid 
        WHERE LEFT(vsc.NAME, 11) = 'Check Point' OR LEFT(vsc.NAME, 8) = 'pointsec' 
    ) cpe 
        ON cpe._resourceguid = vc.[Guid] 
    
    LEFT JOIN Inv_Aex_AC_Client_Status cs 
        ON cs._ResourceGuid = vc.[Guid] 

    /*  DISABLED UNTIL THE USER LOCATION VIEW IS FIXED 
    -- PWU (Windows Users) 
    LEFT JOIN Inv_Global_Windows_Users pwu  
        ON pwu.UserId = vc.[User]  
    
    -- PU (Primary User) 
    LEFT JOIN RM_ResourceUser pu  
        ON pu.[Guid] = pwu._ResourceGuid  
    
    -- UL (User Location)     
    LEFT JOIN v_MIG_User_location ul  
        ON ul._ResourceGuid = pu.[Guid] AND  
        LEN(ul.[Friendly Location]) > 0  
    */ 
    

-- WHERE CLAUSE 
WHERE  
    vc.IsManaged = '1' 
    AND vc.[System Type] <> 'unix' 
    AND vc.[OS Name] NOT LIKE '%server%' 
    AND vc.[MAC Address] NOT LIKE '00-50-56-%'  


-- ORDER CLAUSE 
ORDER BY vc.Name  
"@
$QueryTimeout = 120

#SQL QUERY OBJECTS INTO VARIABLE
#A SQL failure stops the script before any CSV is written or opened.
try {
    $conn = New-ComplianceSqlConnection -ServerInstance $ServerInstance -Database $Database -ConnectionTimeout $ConnectionTimeout -Credential $Credential
    $ds = Invoke-ComplianceQuery -Connection $conn -Query $Query -CommandTimeout $QueryTimeout
}
catch {
    Write-Error "SQL query failed: $($_.Exception.Message)"
    exit 1
}
#ENDREGION SQL QUERY

#CREATE ALTIRIS LIST
$ALTIRIS3 = $ds.Tables[0].rows
$ADRAFT = @()
FOREACH ($ITEM IN $ALTIRIS3){
    
    $ITEMTMP = New-Object PSObject -Property @{
        ALT_Name        = $ITEM.'Computer Name'
        ALT_PC_Loc      = $ITEM.'Computer Location'
        #ALT_User_Loc    = $ITEM.'User Location'
        ALT_User_Loc    = 'DISABLED 4/1/2019'
        ALT_Managed     = $ITEM.Managed
        ALT_OS_Name     = $ITEM.'OS Name'
        ALT_ENC_Stat    = $ITEM.'Encryption Status'
        ALT_ENC_Perc    = $ITEM.ConvertPercentage
        ALT_User_ID     = $ITEM.'User ID'
        ALT_User_Name   = $ITEM.'User Name'
        ALT_BL_LastClientUpdate = $ITEM.'BL_LastClientUpdate'
        ALT_BL_LastInvChange    = $ITEM.'BL_LastInvChange'
        ALT_LastPolicyRequest   = $ITEM.'ALT_LastPolicyRequest'
    }
    $ADRAFT += $ITEMTMP
}
$ALTIRIS2 = $ADRAFT | Group-Object -Property ALT_Name

$ALTIRIS = @()
FOREACH ($ITEM IN $ALTIRIS2){
    
    $ITEMTMP = New-Object PSObject -Property @{
        ALT_Name        = $ITEM.Group.ALT_Name
        ALT_PC_Loc      = $ITEM.Group.ALT_PC_Loc
        #ALT_User_Loc    = $ITEM.Group.ALT_User_Loc
        ALT_User_loc    = 'DISABLED 4/1/2019'
        ALT_Managed     = $ITEM.Group.ALT_Managed
        ALT_OS_Name     = $ITEM.Group.ALT_OS_Name
        ALT_ENC_Stat    = $ITEM.Group.ALT_ENC_Stat
        ALT_ENC_Perc    = $ITEM.Group.ALT_ENC_Perc
        ALT_User_ID     = $ITEM.Group.ALT_User_ID
        ALT_User_Name   = $ITEM.Group.ALT_User_Name
        ALT_BL_LastClientUpdate = $ITEM.Group.ALT_BL_LastClientUpdate
        ALT_BL_LastInvChange    = $ITEM.Group.ALT_BL_LastInvChange    
        ALT_LastPolicyRequest   = $ITEM.Group.ALT_LastPolicyRequest
    }
    $ALTIRIS += $ITEMTMP
}
Get-Status "     SQL Query  " "          Total Time Elapsed:  "

Write-Host "Starting AD Query..."
#REGION AD QUERY COMPUTERS
#An AD failure stops the script before any CSV is written or opened.
try {
    $AD = Get-ComplianceAdComputer -SearchRoot $ComputerSearchRoot
}
catch {
    Write-Error "AD query failed: $($_.Exception.Message)"
    exit 1
}
#ENDREGION AD QUERY COMPUTERS

#REGION AD QUERY BITLOCKER KEYS
try {
    $BLRecovery = @(Invoke-ComplianceAdSearch -Filter '(ObjectCategory=msFVE-RecoveryInformation)' -Property 'name','whencreated','msfve-volumeguid' -SearchRoot $RecoverySearchRoot)
}
catch {
    Write-Error "AD query failed: $($_.Exception.Message)"
    exit 1
}

$BLDRAFT1 = @()
FOREACH ($ITEM IN $BLRecovery){
    #DEBUG LINE
    #$BLRecovery[3788].Properties.adspath.split("'{','}','=',','")
	$BLTMP = $ITEM.Properties.adspath.Split([char[]]"'{},=")
    [STRING]$BLNAME = $BLTMP[5]
    [STRING]$BLCDATE = $BLTMP[1]
	[STRING]$BLPWID = ("{" + $BLTMP[2] + "}")

    $ITEMTMP = New-Object PSObject -Property @{
        BL_Name          = $BLNAME
        BL_Key_Count     = 1
        BL_Created_Date  = $BLCDATE
        BL_PW_ID         = $BLPWID
    }
	$BLDRAFT1 += $ITEMTMP
}
$BLDRAFT2 = $BLDRAFT1 | Group-Object -Property BL_Name | Sort-Object -Property BL_Name

$BLDRAFT3 = @()
FOREACH ($ITEM IN $BLDRAFT2){
    [STRING]$A = $ITEM.Group[0].BL_Name
    [STRING]$B = $ITEM.Group.BL_Key_Count.Count
    [STRING]$C = $ITEM.Group.BL_Created_Date -join ','
    [STRING]$E = $ITEM.Group.BL_PW_ID -join ','

    $ITEMTMP = New-Object PSObject -Property @{
        BL_Name          = $A
        BL_Key_Count     = $B
        BL_Created_Date  = $C
        BL_PW_ID         = $E
    }
    $BLDRAFT3 += $ITEMTMP
}
$BLINFO = $BLDRAFT3 | Sort-Object -Property BL_Name | Select-Object -Property BL_Name,BL_Key_Count,BL_Created_Date,BL_PW_ID

<#
#MAY NOT NEED THIS ANY LONGER SINCE HASH VALUES WERE CHANGED TO STRING SO EXPORT CSV DOESN'T CREATE SYSTEM.OBJECT ENTRIES
$BLKEYS = @()
FOREACH ($ITEM IN $BLDRAFT2){
    $BLPIHASH = $ITEM.Group.BL_PW_ID
    $BLCDHASH = $ITEM.Group.BL_Created_Date

    $ITEMTMP = New-Object PSObject -Property @{
        BL_Name          = $ITEM.Name
        BL_Key_Count     = $ITEM.Count
        BL_Created_Date  = $BLCDHASH
        BL_PW_ID         = $BLPIHASH
    }
    $BLKEYS += $ITEMTMP
}

$BLINFO = $BLKEYS | Select-Object -Property BL_Name,BL_Key_Count,BL_Created_Date,BL_PW_ID
#>

#ENDREGION AD QUERY BITLOCKER KEYS
$BLINFO.Count
Get-Status "     AD Query  " "          Total Time Elapsed:  "

Write-Host "Start Filtering..."
#REGION FILTERING

#ALL AD COMPUTERS (EVERY -ComputerSearchRoot)
$ALLAD = @()
FOREACH ($ITEM IN $AD){
    $ALLAD += $ITEM
}

#JOIN AD & BL DATA
$NEWAD2 = @()
$BLHASH = $BLINFO | Group-Object -Property BL_Name -AsHashTable

$ALLAD | ForEach-Object {
    IF ($BLHASH[$_.AD_Name]){

        $ITEMTMP = New-Object PSObject -Property @{
            AD_Name         = $_.AD_Name
            AD_Created      = $_.AD_Created
            AD_Changed      = $_.AD_Changed
            BL_Name         = $BLHASH[$_.AD_Name][0].BL_Name
            BL_Key_Count    = $BLHASH[$_.AD_Name][0].BL_Key_Count
            BL_Created_Date = $BLHASH[$_.AD_Name][0].BL_Created_Date
            BL_PW_ID        = $BLHASH[$_.AD_Name][0].BL_PW_ID
        }
        $NEWAD2 += $ITEMTMP
    }
    ELSE {

        $ITEMTMP = New-Object PSObject -Property @{
            AD_Name         = $_.AD_Name
            AD_Created      = $_.AD_Created
            AD_Changed      = $_.AD_Changed
            BL_Name         = '---'
            BL_Key_Count    = '---'
            BL_Created_Date = '---'
            BL_PW_ID        = '---'
        }
        $NEWAD2 += $ITEMTMP
    }
}

$ADHASH = $NEWAD2 | Group-Object -Property AD_Name -AsHashTable
$BLINFO | ForEach-Object {
    IF (!($ADHASH[$_.BL_Name])){
        
        $ITEMTMP = New-Object PSObject -Property @{
            AD_Name         = '---'
            AD_Created      = '---'
            AD_Changed      = '---'
            BL_Name         = $_.BL_Name
            BL_Key_Count    = $_.BL_Key_Count
            BL_Created_Date = $_.BL_Created_Date
            BL_PW_ID        = $_.BL_PW_ID
        }
        $NEWAD2 += $ITEMTMP
    }
}
$NEWAD3 = $NEWAD2 | Select-Object -Property AD_Name,AD_Created,BL_Name,BL_Created_Date,BL_Key_Count,BL_PW_ID,AD_Changed

#JOIN AD & ALTIRIS
$NEWAD = @()
$ALTHASH = $ALTIRIS | Group-Object -Property 'ALT_Name' -AsHashTable

$NEWAD3 | ForEach-Object {
    IF ($ALTHASH[$_.AD_Name]){

        $ITEMTMP = New-Object PSObject -Property @{
            AD_Name         = $_.AD_Name
            AD_Created      = $_.AD_Created
            AD_Changed      = $_.AD_Changed
            BL_Name         = $_.BL_Name
            BL_Key_Count    = $_.BL_Key_Count
            BL_Created_Date = $_.BL_Created_Date
            BL_PW_ID        = $_.BL_PW_ID
            ALT_Name        = $ALTHASH[$_.AD_Name][0].ALT_Name
            ALT_PC_Loc      = $ALTHASH[$_.AD_Name][0].ALT_PC_Loc
            #ALT_User_Loc    = $ALTHASH[$_.AD_Name][0].ALT_User_Loc
            ALT_User_Loc    = 'DISABLED 4/1/2019'
            ALT_Managed     = $ALTHASH[$_.AD_Name][0].ALT_Managed
            ALT_OS_Name     = $ALTHASH[$_.AD_Name][0].ALT_OS_Name
            ALT_ENC_Stat    = $ALTHASH[$_.AD_Name][0].ALT_ENC_Stat
            ALT_ENC_Perc    = $ALTHASH[$_.AD_Name][0].ALT_ENC_Perc
            ALT_User_ID     = $ALTHASH[$_.AD_Name][0].ALT_User_ID
            ALT_User_Name   = $ALTHASH[$_.AD_Name][0].ALT_User_Name
            ALT_BL_LastClientUpdate = $ALTHASH[$_.AD_Name][0].ALT_BL_LastClientUpdate
            ALT_BL_LastInvChange    = $ALTHASH[$_.AD_Name][0].ALT_BL_LastInvChange
            ALT_LastPolicyRequest   = $ALTHASH[$_.AD_Name][0].ALT_LastPolicyRequest
        }
        $NEWAD += $ITEMTMP
    }
    ELSE {

        $ITEMTMP = New-Object PSObject -Property @{
            AD_Name         = $_.AD_Name
            AD_Created      = $_.AD_Created
            AD_Changed      = $_.AD_Changed
            BL_Name         = $_.BL_Name
            BL_Key_Count    = $_.BL_Key_Count
            BL_Created_Date = $_.BL_Created_Date
            BL_PW_ID        = $_.BL_PW_ID
            ALT_Name        = '---'
            ALT_PC_Loc      = '---'
            ALT_User_Loc    = '---'
            ALT_Managed     = '---'
            ALT_OS_Name     = '---'
            ALT_ENC_Stat    = '---'
            ALT_ENC_Perc    = '---'
            ALT_User_ID     = '---'
            ALT_User_Name   = '---'
            ALT_BL_LastClientUpdate = '---'
            ALT_BL_LastInvChange    = '---'
            ALT_LastPolicyRequest   = '---'
        }
        $NEWAD += $ITEMTMP
    }
}

$ADHASH2 = $NEWAD | Group-Object -Property AD_Name -AsHashTable
$ALTIRIS | ForEach-Object {
    IF (!($ADHASH2[$_.ALT_Name])){
        
        $ITEMTMP = New-Object PSObject -Property @{
            AD_Name         = '---'
            AD_Created      = '---'
            AD_Changed      = '---'
            BL_Name         = '---'
            BL_Key_Count    = '---'
            BL_Created_Date = '---'
            BL_PW_ID        = '---'
            ALT_Name        = $_.ALT_Name
            ALT_PC_Loc      = $_.ALT_PC_Loc
            #ALT_User_Loc    = $_.ALT_User_Loc
            Alt_User_Loc    = 'DISABLED 4/1/2019'
            ALT_Managed     = $_.ALT_Managed
            ALT_OS_Name     = $_.ALT_OS_Name
            ALT_ENC_Stat    = $_.ALT_ENC_Stat
            ALT_ENC_Perc    = $_.ALT_ENC_Perc
            ALT_User_ID     = $_.ALT_User_ID
            ALT_User_Name   = $_.ALT_User_Name
            ALT_BL_LastClientUpdate = $_.ALT_BL_LastClientUpdate
            ALT_BL_LastInvChange    = $_.ALT_BL_LastInvChange
            ALT_LastPolicyRequest   = $_.ALT_LastPolicyRequest
        }
        $NEWAD += $ITEMTMP
    }
}

$FINALAD = $NEWAD `
    | Sort-Object -Property BL_Name `
    | Select-Object -Property `
        AD_Name `
        ,AD_Created `
        ,AD_Changed `
        ,BL_Name `
        ,BL_Created_Date `
        ,BL_Key_Count `
        ,BL_PW_ID `
        ,ALT_Name `
        ,ALT_PC_Loc `
        ,ALT_User_Loc `
        ,ALT_Managed `
        ,ALT_OS_Name `
        ,ALT_ENC_Stat `
        ,ALT_ENC_Perc `
        ,ALT_User_ID `
        ,ALT_User_Name `
        ,ALT_BL_LastClientUpdate `
        ,ALT_BL_LastInvChange `
        ,ALT_LastPolicyRequest `

#ENDREGION FILTERING
Get-Status "     Objects Filtered  " "          Total Time Elapsed:  "

<#
#VALIDATE
$TEST1 = $NEWAD2.AD_Name
Write ("AD COUNT:  " + $TEST1.Count)
Write ""
$TEST2 = $ALTIRIS.ALT_Name
Write ("ALTIRIS COUNT:  " + $TEST2.Count)
Write ""
$TESTCOMP = Compare-Object $test1 $test2 -IncludeEqual | Group-Object -Property SideIndicator
$TESTCOMP
Write ""
$FINALAD.Count
#>


Write-Host "Creating custom reports in Excel..."
IF (!(Test-Path -Path 'C:\Temp')){
     New-Item -ItemType Directory -Path C:\Temp | Out-Null
}

#COMPUTERS (no VMs) IN AD AND IN ALTIRIS THAT ARE NOT ENCRYPTED
$ESCV1 = "C:\temp\VULNERABLE.csv"
$FINALAD | Where-Object {
     ($_.AD_Name -ne '---' -and $_.ALT_Name -ne '---' -and $_.AD_Name -notlike '*VIEW*') `
        -and ($_.ALT_ENC_STAT -ne 'Bitlocker: Protected') `
        -and ($_.ALT_ENC_STAT -ne 'Checkpoint: Enabled') `
} `
    | Select-Object -Property `
        AD_Name `
        ,AD_Created `
        ,AD_Changed `
        ,BL_Name `
        ,BL_Created_Date `
        ,BL_Key_Count `
        ,BL_PW_ID `
        ,ALT_Name `
        ,ALT_PC_Loc `
        ,ALT_User_Loc `
        ,ALT_Managed `
        ,ALT_OS_Name `
        ,ALT_ENC_Stat `
        ,ALT_ENC_Perc `
        ,ALT_User_ID `
        ,ALT_User_Name `
        ,ALT_BL_LastClientUpdate `
        ,ALT_BL_LastInvChange `
        ,ALT_LastPolicyRequest `
    | Export-Csv -Path $ESCV1 -NoTypeInformation -Force
    #| Out-GridView -Title '***NOT*** ENCRYPTED: PCs in Active Directory & Altiris (no VMs)'

#ENCRYPTED COMPUTERS (no VMs) in AD AND IN ALTIRIS 
$ESCV2 = "C:\temp\ENCRYPTED.csv"
$FINALAD | Where-Object {
    ($_.AD_Name -ne '---' -and $_.ALT_Name -ne '---' -and $_.AD_Name -notlike '*VIEW*') `
        -and ( `
            ($_.ALT_ENC_STAT -eq 'Bitlocker: Protected') `
            -or ($_.ALT_ENC_STAT -eq 'Checkpoint: Enabled') `
        ) `
} `
    | Select-Object -Property `
        AD_Name `
        ,AD_Created `
        ,AD_Changed `
        ,BL_Name `
        ,BL_Created_Date `
        ,BL_Key_Count `
        ,BL_PW_ID `
        ,ALT_Name `
        ,ALT_PC_Loc `
        ,ALT_User_Loc `
        ,ALT_Managed `
        ,ALT_OS_Name `
        ,ALT_ENC_Stat `
        ,ALT_ENC_Perc `
        ,ALT_User_ID `
        ,ALT_User_Name `
        ,ALT_BL_LastClientUpdate `
        ,ALT_BL_LastInvChange `
        ,ALT_LastPolicyRequest `
    | Export-Csv -Path $ESCV2 -NoTypeInformation -Force
    #| Export-Csv -Path ("C:\temp\Bitlocker Report " + ((Get-Date).Year) + ((Get-Date).Month) + ((Get-Date).Day) +".csv") -Force
    #| Out-GridView -Title 'ENCRYPTED: PCs in Active Directory & Altiris (no VMs)'

#ACTIVE DIRECTORY COMPUTERS THAT DO NOT EXIST IN ALTIRIS
$ESCV3 = "C:\temp\IN AD NOT ALTIRIS.csv"
$FINALAD | Where-Object {
    ($_.AD_Name -ne '---' -and $_.ALT_Name -eq '---') `
} `
    | Select-Object -Property `
        AD_Name `
        ,AD_Created `
        ,AD_Changed `
        ,BL_Name `
        ,BL_Created_Date `
        ,BL_Key_Count `
        ,BL_PW_ID `
        ,ALT_Name `
        ,ALT_PC_Loc `
        ,ALT_User_Loc `
        ,ALT_Managed `
        ,ALT_OS_Name `
        ,ALT_ENC_Stat `
        ,ALT_ENC_Perc `
        ,ALT_User_ID `
        ,ALT_User_Name `
        ,ALT_BL_LastClientUpdate `
        ,ALT_BL_LastInvChange `
        ,ALT_LastPolicyRequest `
    | Export-Csv -Path $ESCV3 -NoTypeInformation -Force
    #| Out-GridView -Title '**ACTIVE DIRECTORY COMPUTERS NOT IN ALTIRIS'

#ALTIRIS COMPUTERS THAT DO NOT EXIST IN ACTIVE DIRECTORY
$ESCV4 = "C:\temp\IN ALTIRIS NOT AD.csv"
$FINALAD | Where-Object {
    ($_.AD_Name -eq '---' -and $_.ALT_Name -ne '---') `
} `
    | Select-Object -Property `
        AD_Name `
        ,AD_Created `
        ,AD_Changed `
        ,BL_Name `
        ,BL_Created_Date `
        ,BL_Key_Count `
        ,BL_PW_ID `
        ,ALT_Name `
        ,ALT_PC_Loc `
        ,ALT_User_Loc `
        ,ALT_Managed `
        ,ALT_OS_Name `
        ,ALT_ENC_Stat `
        ,ALT_ENC_Perc `
        ,ALT_User_ID `
        ,ALT_User_Name `
        ,ALT_BL_LastClientUpdate `
        ,ALT_BL_LastInvChange `
        ,ALT_LastPolicyRequest `
    | Export-Csv -Path $ESCV4 -NoTypeInformation -Force
    #| Out-GridView -Title '**ACTIVE DIRECTORY COMPUTERS NOT IN ALTIRIS'

Start-Sleep -Seconds 5
#EXCEL REPORTS
$xl = New-Object -ComObject Excel.Application
$xl.Visible = $TRUE
$wb = $xl.Workbooks.Open($ESCV4)
    $WB2 = $xl.WorkBooks.Open($ESCV3)
    
    $WB2.ActiveSheet.Move($WB.ActiveSheet)
    $WB3 = $xl.WorkBooks.Open($ESCV2)
    $WB3.ActiveSheet.Move($WB.ActiveSheet)
    $WB4 = $xl.WorkBooks.Open($ESCV1)
    $WB4.ActiveSheet.Move($WB.ActiveSheet)

$xl.Visible = $TRUE

Get-Status "     Custom Report Complete  " "          Total Time Elapsed:  "
#ENDREGION AD QUERY & COLLECTION

    Write-Host "DONE!!!!!"
    Write-Host ""
    Write-Host ""            
$elapsed.stop()

Write-Host "Closing in 10 seconds..."
Start-Sleep -Seconds 10

<#
#THIS SECTION IS USED TO VALIDATE DATA RETURNED IN ALL QUERIES
#FOR EXAMPLE:  TOTAL OBJECTS SHOULD = THE DIFFERENCE BETWEEN AD, BL, & ALTIRIS


#VALIDATION 2
Write-Host "ALLAD vs Bitlocker"
$AADVSBL = Compare-Object ($ALLAD.AD_Name | Select-Object -Unique) ($BLINFO.BL_Name | Select-Object -Unique) -IncludeEqual | Group-Object -Property SideIndicator
$AADVSBL | Select-Object -Property Count,Name | FT -AutoSize
Write-Host "Total"
Write-Host "-----"
$TOTAL2 = (($AADVSBL | Select-Object -ExpandProperty Count | Measure-Object -Sum).Sum)
$TOTAL2
Write-Host " "
Write-Host "Does ALLAD & BLINFO = NEWAD3?"
IF (($NEWAD3.Count - $Total2) -eq '0') {
    Write-Host "     YES: Values are equal..."
}
ELSE {
    Write-Warning "     NO: Please check totals..."
}

#VALIDATION 3
Write-Host "NEWAD3 vs Altiris"
$NADVSFAD = Compare-Object (($NEWAD2 | Where-Object {$_.AD_Name -ne "---"}).AD_Name | Select-Object -Unique) ($ALTIRIS.ALT_Name) -IncludeEqual | Group-Object -Property SideIndicator
$NADVSFAD | Select-Object -Property Count,Name | FT -AutoSize
$NADVSFAD2 = $NEWAD2 | Where-Object {$_.AD_Name -eq "---"}
Write-Host "Total"
Write-Host "-----"
$TOTAL3 = (($NADVSFAD | Select-Object -ExpandProperty Count | Measure-Object -Sum).Sum)
$TOTAL3
Write-Host " "
Write-Host "Does ALLAD & BLINFO = NEWAD3?"
IF (($FINALAD.Count - ($Total3 + ($NADVSFAD2.Count))) -eq '0') {
    Write-Host "     YES: Values are equal..."
}
ELSE {
    Write-Warning "     NO: Please check totals..."
}

#>