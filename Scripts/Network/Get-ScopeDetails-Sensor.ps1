$AccessibleDHCPServers = @()
$DHCPServers = Get-DhcpServerInDC | Where-Object {$_.IPAddress -ne "10.0.0.12"} 

ForEach ($DHCPServer in $DHCPServers) {
    Try {
        Get-DhcpServerVersion -ComputerName $DHCPServer.DnsName -ErrorAction Stop | Out-Null
        $AccessibleDHCPServers += $DHCPServer
    }
    Catch { }
}

$TargetScopes = @()
$AllScopeVendorOptionValues = @()

ForEach ($AccessibleDHCPServer in $AccessibleDHCPServers) {
    $Scopes = Get-DhcpServerv4Scope -ComputerName $AccessibleDHCPServer.DnsName.Trim() `
        -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Active' } | `
        Select-Object *, @{name = 'DHCPServerName'; e = { $AccessibleDHCPServer.DnsName.Trim() } }
    $TargetScopes += $Scopes
}
ForEach ($TargetScope in $TargetScopes) {
    $ScopeVendorOptionValues = Get-DhcpServerv4OptionValue -ComputerName $TargetScope.DHCPServerName `
        -ScopeId $TargetScope.ScopeId -OptionId 1 `
        -ErrorAction Ignore | `
        Select-Object *
    $AllScopeVendorOptionValues += $ScopeVendorOptionValues
}

# $DHCPServerOptionValues = Get-DhcpServerv4OptionValue -ComputerName $AccessibleDHCPServer.DnsName `
# -All -OptionId 1 `
#     -ErrorAction SilentlyContinue
# $AllServerOptionValues += $DHCPServerOptionValues
#}

#$TargetScopes | Select-Object -Property Name, ScopeId, SubnetMask, StartRange, EndRange

