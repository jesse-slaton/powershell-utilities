<#
.SYNOPSIS
    Reports whether the Altiris primary user of this computer is in a matching AD group.

.DESCRIPTION
    Reads the Altiris Basic Inventory (Altiris.BasicInventory COM object), takes the
    account name in column c2 of the 'AeX AC Primary User' data class, and looks that
    account up in Active Directory with an [adsisearcher] query on samAccountName. The
    user's group CNs (leaving out groups whose distinguished name contains
    'ReportingGroup') are sorted and joined with commas, and the script outputs the
    result of matching that string against the MemberOf value with -match: True or False.

    The MemberOf value is a regular expression, not an exact group name, so it also
    matches group names that only contain it. Read-only.

    The script has no param() block. MemberOf is a Tanium sensor parameter: the
    '||MemberOf||' token on the first line is replaced by Tanium with the URL-encoded
    value before the script runs, and the script decodes it with
    [System.Uri]::UnescapeDataString.

.EXAMPLE
    .\AD Query - Altiris Primary User Group Member.ps1

    Run by Tanium as a sensor with the MemberOf parameter set to a group name; outputs
    True or False.

.NOTES
    Requires the Altiris (Symantec Management) Agent, which provides the
    Altiris.BasicInventory COM object, a domain-joined computer that can reach a domain
    controller, and the Tanium Client to substitute the ||MemberOf|| parameter. Run
    outside Tanium, the literal text '||MemberOf||' is used as the pattern.
#>
[String]$MemberOf = [System.Uri]::UnescapeDataString('||MemberOf||')
function Get-DomainUser {
    PARAM($AccountName)
    $Search = [adsisearcher]"(&(objectCategory=person)(objectClass=User)(samaccountname=$AccountName))"
    foreach ($user in $($Search.FindOne())) {
        New-Object -TypeName PSObject -Property @{
            "MemberOf"   = $(($user.Properties.memberof | Where-object {$_ -notmatch 'ReportingGroup'} | Sort-Object) -replace '^(CN=)(.*?),.*$', '$2') -join ','
        }
    }
}

$BasicInventory = New-Object -ComObject Altiris.BasicInventory
[xml]$inventory = $BasicInventory.Inventory
$PrimaryUser = ($inventory.message.body.inventory.dataClass | `
    Where-Object {$_.name -eq 'AeX AC Primary User'}).data.childnodes.row
$UserDetails = Get-DomainUser -AccountName "$($PrimaryUser.c2.Trim())"

$UserDetails.MemberOf -match "$MemberOf"