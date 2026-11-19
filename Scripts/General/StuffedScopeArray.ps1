<#
.SYNOPSIS
    Sensor that looks up this computer's location from its lowest-metric adapter's network in a local scope list.

.DESCRIPTION
    If C:\DesktopSupportTools\ComputerLocations.txt exists, the script reads it as a
    semicolon-delimited CSV with ScopeID, Location and Specific columns. It picks one
    adapter from Win32_NetworkAdapterConfiguration: IP-enabled, description not
    matching "loop" or "Hyper", sorted by GatewayCostMetric, first one kept. The
    address checks (-notmatch ':' and -notlike '169.*') run against the IPAddress
    array, so they return the non-matching elements instead of rejecting the adapter:
    an adapter passes if it has at least one address without ':' and at least one
    address not like 169.*. When the kept adapter has more than one address (for
    example IPv4 and IPv6), IPAddress and IPSubnet are arrays and the [ipaddress]
    casts fail with an error. For a single-address adapter it computes the network
    address (IP AND subnet mask), keeps the rows whose ScopeID matches that address
    (regular-expression -match), and writes one line built from the first matching
    row, with quotes removed:

        <Network>|<Location>|<Specific>

    If the file does not exist, the script writes nothing. Read-only.

.EXAMPLE
    .\StuffedScopeArray.ps1

    Writes the network address and location for this computer's primary network.

.NOTES
    Requires C:\DesktopSupportTools\ComputerLocations.txt to be staged on the computer.
    Uses Get-WmiObject, so Windows PowerShell 5.1 only. No admin rights needed.
#>

$CSV = 'C:\DesktopSupportTools\ComputerLocations.txt'

If (Test-Path -Path $CSV) {
    $ScopeArray = (Import-Csv -Path $CSV -Delimiter ';')
    $Query = "Select Description, IPAddress, IPEnabled, IPSubnet, GatewayCostMetric from Win32_NetworkAdapterConfiguration Where IPEnabled=True"
    $IPAddresses = Get-WmiObject -Query $Query | `
        Where-Object {
        $_.IPEnabled -eq $True -and `
            $_.Description -notmatch 'loop|Hyper' -and `
            $_.IPAddress -notmatch ':' -and `
            $_.IPAddress -notlike '169.*'
    } | `
        Sort-Object -Property GatewayCostMetric | `
        Select-Object -First 1 
    [ipaddress]$IP = $IPAddresses.IPAddress.Trim()
    [ipaddress]$Mask = $IPAddresses.IPSubnet.Trim()
    [ipaddress]$NetAddr = ($IP.Address -band $mask.Address)

 [String] ($ScopeArray | Where-Object {$_.ScopeID -match $NetAddr.IPAddressToString} | `
            Select-Object @{Name = "Network"; Expression = {$NetAddr.IPAddressToString}}, Location, Specific | `
            ConvertTo-Csv -NoTypeInformation -Delimiter '|')[1] -replace '"', ''
}