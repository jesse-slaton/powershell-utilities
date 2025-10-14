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