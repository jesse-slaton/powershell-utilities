#Requires -Version 3.0
$NCSIProbeHost = (Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet).ActiveWebProbeHost
$NCSIDNSAddress = (Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet).ActiveDnsProbeHost
$ResolvedNCSIProbeHost = Resolve-DnsName -Name $NCSIProbeHost -DnsOnly -Type A
$ResolvedNCSIProbeHostname = $ResolvedNCSIProbeHost.Name[0]
$NCSIIPAddresses = $ResolvedNCSIProbeHost.ipaddress -join "|"

$ResolvedDNSHost = Resolve-DnsName -Name $NCSIDNSAddress -DnsOnly -Type A
$ResolvedDNSHostname = $ResolvedDNSHost.Name
$ResolvedDNSIPAddress = $ResolvedDNSHost.ipaddress

try {
    if ( (Invoke-Webrequest ("http://{0}/{1}" -f (Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet).ActiveWebProbeHost,
                (Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet).ActiveWebProbePath)
        ).Content -eq (Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet).ActiveWebProbeContent ) { 

        # IP4 web request was successful
        
        Write-Verbose 'IP4 web probe succeeded.'
        
        $ProbeResults = $true 

    }
}
catch {
    # Ignore errors

    Write-Verbose 'IP4 web probe failed.'
    $ProbeResults = $false 

}

Try {
    $Networks = Get-WmiObject Win32_NetworkAdapterConfiguration `
        -ErrorAction Stop | Where-Object { $_.IPEnabled }
}
Catch {
    Write-Warning "Error occurred while querying."
    Continue
}
foreach ($Network in $Networks) {
    [ipaddress] $IPAddress = $Network.IpAddress[0]
    [ipaddress] $SubnetMask = $Network.IPSubnet[0]
    [ipaddress] $NetAddr = ($IPAddress.Address -band $SubnetMask.Address)
    $RouteCostMetric = $Network.GatewayCostMetric
    $OutputObj = New-Object -Type PSObject
    $OutputObj | Add-Member -MemberType NoteProperty -Name IPAddress -Value $IPAddress
    $OutputObj | Add-Member -MemberType NoteProperty -Name SubnetMask -Value $SubnetMask
    $OutputObj | Add-Member -MemberType NoteProperty -Name Network -Value $NetAddr
    $OutputObj | Add-Member -MemberType NoteProperty -Name RouteCostMetric -Value $RouteCostMetric
}
$PrimaryIP = $OutputObj | Sort-Object -Property RouteCostMetric | Select-Object -First 1

Write-Host "$ResolvedNCSIProbeHostname, $NCSIIPAddresses, $ProbeResults, $ResolvedDNSHostname, $ResolvedDNSIPAddress, $($PrimaryIP.Network)"