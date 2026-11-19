<#
.SYNOPSIS
    Disables NetBIOS over TCP/IP on every IP-enabled network adapter of the local computer.

.DESCRIPTION
    Queries Win32_NetworkAdapterConfiguration for adapters with IPEnabled = TRUE and
    calls SetTcpipNetbios(2) on each one, which sets the adapter's NetBIOS setting to
    Disabled. Outputs the WMI method result object for each adapter; check its
    ReturnValue property for the outcome.

.EXAMPLE
    .\DisableNetBIOS.ps1

    Disables NetBIOS over TCP/IP on all IP-enabled adapters.

.NOTES
    Requires administrator rights. Uses Get-WmiObject, which exists only in Windows
    PowerShell 5.1 (not PowerShell 7).
#>
$nics = Get-WmiObject -Query 'SELECT * from Win32_NetworkAdapterConfiguration WHERE IPEnabled = TRUE'
ForEach ($nic in $nics) {
    $nic.SetTcpipNetbios(2)
}