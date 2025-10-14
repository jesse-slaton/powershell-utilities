[String]$Manager = [System.Uri]::UnescapeDataString('||Manager||')
function Get-DomainUser {
    PARAM($AccountName)
    $Search = [adsisearcher]"(&(objectCategory=person)(objectClass=User)(samaccountname=$AccountName))"
    foreach ($user in $($Search.FindOne())) {
        New-Object -TypeName PSObject -Property @{
            "Manager"     = $($user.Properties.manager  -replace '(CN=)(.*?),.*', '$2')
        }
    }
}

$BasicInventory = New-Object -ComObject Altiris.BasicInventory
[xml]$inventory = $BasicInventory.Inventory
$PrimaryUser = ($inventory.message.body.inventory.dataClass | `
    Where-Object {$_.name -eq 'AeX AC Primary User'}).data.childnodes.row
$UserDetails = Get-DomainUser -AccountName "$($PrimaryUser.c2.Trim())"

$UserDetails.Manager -match "$Manager"