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