<#
.SYNOPSIS
    Collects the active DHCP scopes and their option 1 values from every reachable authorized DHCP server.

.DESCRIPTION
    Lists the DHCP servers authorized in Active Directory (Get-DhcpServerInDC), leaving
    out one server whose IP address is hard-coded in the script. A server counts as
    reachable when Get-DhcpServerVersion succeeds against its DNS name; the others are
    skipped silently.

    For each reachable server it gets the active IPv4 scopes, adding a DHCPServerName
    property, into $TargetScopes. For each of those scopes it reads the scope-level
    value of option 1 (Get-DhcpServerv4OptionValue -OptionId 1, default vendor class)
    into $AllScopeVendorOptionValues. Errors from that read are ignored.

    The output lines are commented out, so the script writes nothing to the pipeline
    and changes nothing. Dot-source it to inspect the two variables.

.EXAMPLE
    . .\Get-ScopeDetails-Sensor.ps1
    $TargetScopes | Select-Object DHCPServerName, Name, ScopeId

    Dot-sources the script and lists the active scopes it found.

.NOTES
    Requires the DhcpServer module (RSAT DHCP tools), a domain-joined computer, network
    access to the DHCP servers and rights to read their configuration. Windows
    PowerShell 5.1 (the DhcpServer module is a Windows PowerShell module).
#>
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

