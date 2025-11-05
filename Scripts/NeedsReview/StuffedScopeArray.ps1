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