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