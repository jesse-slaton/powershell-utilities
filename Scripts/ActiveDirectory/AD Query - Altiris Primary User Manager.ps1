<#
.SYNOPSIS
    Reports whether the manager of the Altiris primary user matches a given name.

.DESCRIPTION
    Reads the Altiris Basic Inventory (Altiris.BasicInventory COM object), takes the
    account name in column c2 of the 'AeX AC Primary User' data class, and looks that
    account up in Active Directory with an [adsisearcher] query on samAccountName. It
    takes the CN of the user's manager attribute and outputs the result of matching it
    against the Manager value with -match: True or False. The Manager value is a regular
    expression, so a partial name also matches. Read-only.

    The script has no param() block. Manager is a Tanium sensor parameter: the
    '||Manager||' token on the first line is replaced by Tanium with the URL-encoded
    value before the script runs, and the script decodes it with
    [System.Uri]::UnescapeDataString.

.EXAMPLE
    .\AD Query - Altiris Primary User Manager.ps1

    Run by Tanium as a sensor with the Manager parameter set to a manager's name;
    outputs True or False.

.NOTES
    Requires the Altiris (Symantec Management) Agent, which provides the
    Altiris.BasicInventory COM object, a domain-joined computer that can reach a domain
    controller, and the Tanium Client to substitute the ||Manager|| parameter. Run
    outside Tanium, the literal text '||Manager||' is used as the pattern.
#>
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