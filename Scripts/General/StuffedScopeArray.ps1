<#
.SYNOPSIS
    Sensor that looks up this computer's location from its primary IPv4 network in a local scope list.

.DESCRIPTION
    If C:\DesktopSupportTools\ComputerLocations.txt exists, the script reads it as a
    semicolon-delimited CSV with ScopeID, Location and Specific columns. It picks the
    primary adapter from Win32_NetworkAdapterConfiguration: IP-enabled, description not
    matching "loop" or "Hyper", address not IPv6 or 169.*, lowest GatewayCostMetric.
    It computes the network address (IP AND subnet mask), keeps the rows whose ScopeID
    matches that address (regular-expression -match), and writes one line built from
    the first matching row, with quotes removed:

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