<#
.SYNOPSIS
    Sets the Microsoft vendor-class DHCP option 1 to 0x2 (disable NetBIOS over TCP/IP) on every reachable authorized DHCP server.

.DESCRIPTION
    Lists the DHCP servers authorized in Active Directory (Get-DhcpServerInDC), leaving
    out one server whose IP address is hard-coded in the script. A server counts as
    reachable when Get-DhcpServerVersion succeeds against its DNS name; the others are
    skipped silently.

    For each reachable server and for each of the vendor classes
    "Microsoft Windows 2000 Options" and "Microsoft Options", the script reads the
    option 1 definition and its current server-level value, then sets the server-level
    value to 0x2 with Set-DhcpServerv4OptionValue. If a set fails, it writes an error
    and ends the process with exit code 1 ([Environment]::Exit), which also closes an
    interactive PowerShell session.

    Output is a Format-Table of DHCP Server, Vendor Class, Option, OptionId,
    Initial Result and Final Result. Initial Result is the value before the change, or
    "Not Set". Set-DhcpServerv4OptionValue is called without -PassThru and returns
    nothing, so Final Result always shows "Not Set" even when the change succeeded.

.EXAMPLE
    .\Set-DhcpNetBiosOverTcpIpOption.ps1

    Applies the option on every reachable DHCP server and shows the before and after
    table.

.NOTES
    Requires the DhcpServer module (RSAT DHCP tools), a domain-joined computer, network
    access to the DHCP servers, and DHCP administrator rights on them. Changes the
    server-level option on each server (inherited by scopes that do not set their
    own value); there is no -WhatIf. Windows
    PowerShell 5.1 (the DhcpServer module is a Windows PowerShell module).
#>
$AccessibleDHCPServers = @()
$DHCPServers = Get-DhcpServerInDC | Where-Object { $_.IPAddress -ne "10.0.0.12" } 
$VendorClasses = @("Microsoft Windows 2000 Options", "Microsoft Options")
$VendorOptionStatus = @()
$NewValue = 0x2

ForEach ($DHCPServer in $DHCPServers) {
    Try {
        Get-DhcpServerVersion -ComputerName $DHCPServer.DnsName -ErrorAction Stop | Out-Null
        $AccessibleDHCPServers += $DHCPServer
    }
    Catch { }
}

ForEach ($AccessibleDHCPServer in $AccessibleDHCPServers) {
    ForEach ($VendorClass in $VendorClasses) {
        $OptionDefinition = Get-DhcpServerv4OptionDefinition -ComputerName $AccessibleDHCPServer.DnsName `
            -VendorClass $VendorClass -OptionId 1 | Select-Object Name, OptionId, VendorClass
        $GetOptionResult = Get-DhcpServerv4OptionValue -ComputerName $AccessibleDHCPServer.DnsName  `
            -VendorClass $VendorClass -OptionId 1 -ErrorAction Ignore | Select-Object Value
        If ($null -eq $GetOptionResult.Value) {
            $InitialResult = "Not Set"
        }
        Else {
            $InitialResult = $GetOptionResult | Select-Object -ExpandProperty Value
        }
        Try {
            $SetOptionResult = Set-DhcpServerv4OptionValue -ComputerName $AccessibleDHCPServer.DnsName  `
                -VendorClass $VendorClass -OptionId 1 -Value $NewValue -ErrorAction Stop | Select-Object Value
            #-WhatIf
        }
        Catch {
            Write-Error -Message "Could not set the Option value $NewValue for $($OptionDefinition.Name) on $($AccessibleDHCPServer.DnsName)"
            [Environment]::Exit(1)
        }
        If ($null -eq $SetOptionResult.Value) {
            $FinalResult = "Not Set"
        }
        Else {
            $FinalResult = $SetOptionResult.Value | Select-Object -ExpandProperty Value
        }

        $Object = [pscustomobject]@{
            'DHCP Server'    = $AccessibleDHCPServer.DnsName
            'Vendor Class'   = $OptionDefinition.VendorClass
            Option           = $OptionDefinition.Name
            OptionId         = $OptionDefinition.OptionId
            'Initial Result' = $InitialResult
            'Final Result'   = $FinalResult
        }
        $VendorOptionStatus += $Object
    }
}
$VendorOptionStatus | Format-Table -AutoSize