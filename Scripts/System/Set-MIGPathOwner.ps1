<#
.SYNOPSIS
    Makes the Altiris primary user the owner of C:\MIG and grants that user Full Control.

.DESCRIPTION
    Reads the agent's basic inventory XML through the Altiris.BasicInventory COM object
    and takes the primary user from the 'AeX AC Primary User' data class as
    <Domain>\<User> (columns c3 and c2). It then sets that account as the owner of
    C:\MIG and of every file and folder under it (Get-ChildItem -Force -Recurse), and
    adds a Full Control access rule for the account on C:\MIG that is inherited by
    subfolders and files. Produces no output.

.EXAMPLE
    .\Set-MIGPathOwner.ps1

    Gives the computer's Altiris primary user ownership of C:\MIG and Full Control on it.

.NOTES
    Requires administrator rights and the Altiris (Symantec Management) Agent with
    basic inventory data available. C:\MIG must exist.
#>


Function GetAltirisPrimaryUser {
    $BasicInventory = New-Object -ComObject Altiris.BasicInventory
    [xml]$inventory = $BasicInventory.Inventory
    $PrimaryUser = ($inventory.message.body.inventory.dataClass | `
                Where-Object { $_.name -eq 'AeX AC Primary User' }).data.childnodes.row
    Return "$($PrimaryUser.c3.Trim())\$($PrimaryUser.c2.Trim())"
}
[string]$Primary = $(GetAltirisPrimaryUser)

$identityReference = [System.Security.Principal.NTAccount]::new($Primary)
Get-Item C:\MIG `
| ForEach-Object { $_ ; $_ | Get-ChildItem -Force -Recurse } `
| ForEach-Object { $acl = $_ | Get-Acl; $acl.SetOwner($identityReference); $_ | Set-Acl -AclObject $acl }

$path = 'C:\MIG'

$acl = Get-Acl -Path $path
$accessrule = New-Object System.Security.AccessControl.FileSystemAccessRule ($Primary, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')
$acl.SetAccessRule($accessrule)
Set-Acl -Path $path -AclObject $acl