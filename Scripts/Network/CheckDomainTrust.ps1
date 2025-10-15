 $DCCount = (Resolve-DnsName -Name _ldap._tcp.dc._msdcs.corp.contoso.com -Type Any -ErrorAction SilentlyContinue).Count
 If ($DCCount) {
     $Results = Test-ComputerSecureChannel
 }
 Else {
     $Results = 'Unable to resolve domain controller addresses.'
 }
 Write-Output $Results