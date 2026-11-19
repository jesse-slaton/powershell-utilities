<#
.SYNOPSIS
    Outputs Active Directory details for the Altiris primary user of this computer.

.DESCRIPTION
    Reads the Altiris Basic Inventory (Altiris.BasicInventory COM object), takes the
    account name in column c2 of the 'AeX AC Primary User' data class, and looks that
    account up in Active Directory with an [adsisearcher] query on samAccountName.
    Outputs one pipe-delimited line:

        <UserName>|<DisplayName>|<Department>|<Manager>|<MemberOf>

    Manager is the CN of the manager's distinguished name. MemberOf is a comma-separated,
    sorted list of group CNs, leaving out groups whose distinguished name contains
    'ReportingGroup'. Fields that cannot be read are empty. Read-only.

.EXAMPLE
    .\AD Query - Altiris Primary User Details.ps1

    <UserName>|<DisplayName>|<Department>|<ManagerName>|<Group1>,<Group2>

.NOTES
    Requires the Altiris (Symantec Management) Agent, which provides the
    Altiris.BasicInventory COM object, and a domain-joined computer that can reach a
    domain controller. Written as a sensor-style script: it takes no parameters and
    writes a single line.
#>


function Get-DomainUser {
    PARAM($AccountName)
    $Search = [adsisearcher]"(&(objectCategory=person)(objectClass=User)(samaccountname=$AccountName))"
    foreach ($user in $($Search.FindOne())) {
        New-Object -TypeName PSObject -Property @{
            "DisplayName" = $($user.properties.displayname)
            "UserName"    = $($user.properties.samaccountname)
            "Department"  = $($user.properties.department)
            "Manager"     = $($user.Properties.manager  -replace '(CN=)(.*?),.*', '$2')
            "MemberOf"   = $(($user.Properties.memberof | Where-object {$_ -notmatch 'ReportingGroup'} | Sort-Object) -replace '^(CN=)(.*?),.*$', '$2') -join ','
        }
    }
}

$BasicInventory = New-Object -ComObject Altiris.BasicInventory
[xml]$inventory = $BasicInventory.Inventory
$PrimaryUser = ($inventory.message.body.inventory.dataClass | `
    Where-Object {$_.name -eq 'AeX AC Primary User'}).data.childnodes.row
$UserDetails = Get-DomainUser -AccountName "$($PrimaryUser.c2.Trim())"

Write-Output "$($UserDetails.UserName)|$($UserDetails.DisplayName)|$($UserDetails.Department)|$($UserDetails.Manager)|$($UserDetails.MemberOf)"