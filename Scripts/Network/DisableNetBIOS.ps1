<#
.SYNOPSIS
    Disables NetBIOS over TCP/IP on every IP-enabled network adapter of the local computer.

.DESCRIPTION
    Queries Win32_NetworkAdapterConfiguration for adapters with IPEnabled = TRUE and
    calls SetTcpipNetbios(2) on each one, which sets the adapter's NetBIOS setting to
    Disabled. Outputs the CIM method result object for each adapter; check its
    ReturnValue property for the outcome (0 means success).

.EXAMPLE
    .\DisableNetBIOS.ps1

    Disables NetBIOS over TCP/IP on all IP-enabled adapters.

.NOTES
    Requires administrator rights. Uses the CIM cmdlets, so it runs on Windows
    PowerShell 5.1 and PowerShell 7.
#>
$nics = Get-CimInstance -Query 'SELECT * from Win32_NetworkAdapterConfiguration WHERE IPEnabled = TRUE'
ForEach ($nic in $nics) {
    Invoke-CimMethod -InputObject $nic -MethodName SetTcpipNetbios -Arguments @{ TcpipNetbiosOptions = [uint32]2 }
}