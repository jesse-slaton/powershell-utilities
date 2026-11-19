<#
.SYNOPSIS
    Tests the computer's secure channel to its domain when domain controller SRV records resolve.

.DESCRIPTION
    Looks up the _ldap._tcp.dc._msdcs SRV records for a domain name that is hard-coded
    in the script (currently the placeholder corp.contoso.com; edit it for your domain).
    If any record resolves, runs Test-ComputerSecureChannel (without -Repair) and
    outputs its result, True or False. If nothing resolves, outputs the string
    "Unable to resolve domain controller addresses."

    Changes nothing.

.EXAMPLE
    .\CheckDomainTrust.ps1

    Outputs True when the secure channel is healthy, False when it is broken, or the
    resolution message when no domain controller is found.

.NOTES
    Requires a domain-joined computer and DNS access to the domain. Test-ComputerSecureChannel
    exists only in Windows PowerShell 5.1 (not PowerShell 7). Resolve-DnsName needs the
    DnsClient module (Windows 8 / Server 2012 or later).
#>
 $DCCount = (Resolve-DnsName -Name _ldap._tcp.dc._msdcs.corp.contoso.com -Type Any -ErrorAction SilentlyContinue).Count
 If ($DCCount) {
     $Results = Test-ComputerSecureChannel
 }
 Else {
     $Results = 'Unable to resolve domain controller addresses.'
 }
 Write-Output $Results