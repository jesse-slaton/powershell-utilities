# NOTE: Requires external repo at D:\dev\repos\Indented.Net.IP
# Original repo: https://git.example.com/sydlexius/Indented.Net.IP.git

function ConvertToNetwork {
    # .SYNOPSIS
    #   Converts IP address formats to a set a known styles.
    # .DESCRIPTION
    #   Internal use only.
    #
    #   ConvertToNetwork ensures consistent values are recorded from parameters which must handle differing addressing formats. This Cmdlet allows all other the other functions in this module to offload parameter handling.
    # .PARAMETER IPAddress
    #   Either a literal IP address, a network range expressed as CIDR notation, or an IP address and subnet mask in a string.
    # .PARAMETER SubnetMask
    #   A subnet mask as an IP address.
    # .INPUTS
    #   System.String
    # .OUTPUTS
    #   Indented.Net.IP.Network
    # .NOTES
    #   Author: Chris Dent
    #
    #   Change log:
    #     05/03/2016 - Chris Dent - Refactored and simplified.
    #     14/01/2014 - Chris Dent - Created.

    param(
        [Parameter(Mandatory = $true, Position = 1)]
        [String]$IPAddress,

        [Parameter(Position = 2)]
        [AllowNull()]
        [String]$SubnetMask
    )

    if (-not $Script:ValidSubnetMaskValues) {
        $Script:ValidSubnetMaskValues =
        "0.0.0.0", "128.0.0.0", "192.0.0.0",
        "224.0.0.0", "240.0.0.0", "248.0.0.0", "252.0.0.0",
        "254.0.0.0", "255.0.0.0", "255.128.0.0", "255.192.0.0",
        "255.224.0.0", "255.240.0.0", "255.248.0.0", "255.252.0.0",
        "255.254.0.0", "255.255.0.0", "255.255.128.0", "255.255.192.0",
        "255.255.224.0", "255.255.240.0", "255.255.248.0", "255.255.252.0",
        "255.255.254.0", "255.255.255.0", "255.255.255.128", "255.255.255.192",
        "255.255.255.224", "255.255.255.240", "255.255.255.248", "255.255.255.252",
        "255.255.255.254", "255.255.255.255"
    }

    $Network = [PSCustomObject]@{
        IPAddress  = $null
        SubnetMask = $null
        MaskLength = 0
    } | Add-Member -TypeName 'Indented.Net.IP.Network' -PassThru

    # Override ToString
    $Network | Add-Member ToString -MemberType ScriptMethod -Force -Value {
        '{0}/{1}' -f $this.IPAddress, $this.MaskLength
    }

    if (-not $psboundparameters.ContainsKey('SubnetMask') -or $SubnetMask -eq '') {
        $IPAddress, $SubnetMask = $IPAddress.Split('\/ ', [StringSplitOptions]::RemoveEmptyEntries)
    }

    # IPAddress

    while ($IPAddress.Split('.').Count -lt 4) {
        $IPAddress += '.0'
    }

    if ([IPAddress]::TryParse($IPAddress, [Ref]$null)) {
        $Network.IPAddress = [IPAddress]$IPAddress
    }
    else {
        $ErrorRecord = New-Object System.Management.Automation.ErrorRecord(
            (New-Object ArgumentException 'Invalid IP address.'),
            'InvalidIPAddress',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $IPAddress
        )
        throw $ErrorRecord
    }

    # SubnetMask

    if ($null -eq $SubnetMask -or $SubnetMask -eq '') {
        $Network.SubnetMask = [IPAddress]$Script:ValidSubnetMaskValues[32]
        $Network.MaskLength = 32
    }
    else {
        $MaskLength = 0
        if ([Int32]::TryParse($SubnetMask, [Ref]$MaskLength)) {
            if ($MaskLength -ge 0 -and $MaskLength -le 32) {
                $Network.SubnetMask = [IPAddress]$Script:ValidSubnetMaskValues[$MaskLength]
                $Network.MaskLength = $MaskLength
            }
            else {
                $ErrorRecord = New-Object System.Management.Automation.ErrorRecord(
                    (New-Object ArgumentException 'Mask length out of range (expecting 0 to 32).'),
                    'InvalidMaskLength',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $SubnetMask
                )
                throw $ErrorRecord
            }
        }
        else {
            while ($SubnetMask.Split('.').Count -lt 4) {
                $SubnetMask += '.0'
            }
            $MaskLength = $Script:ValidSubnetMaskValues.IndexOf($SubnetMask)

            if ($MaskLength -ge 0) {
                $Network.SubnetMask = [IPAddress]$SubnetMask
                $Network.MaskLength = $MaskLength
            }
            else {
                $ErrorRecord = New-Object System.Management.Automation.ErrorRecord(
                    (New-Object ArgumentException 'Invalid subnet mask.'),
                    'InvalidSubnetMask',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $SubnetMask
                )
                throw $ErrorRecord
            }
        }
    }

    return $Network
}
function ConvertTo-DecimalIP {
    # .SYNOPSIS
    #   Converts a Decimal IP address into a 32-bit unsigned integer.
    # .DESCRIPTION
    #   ConvertTo-DecimalIP takes a decimal IP, uses a shift operation on each octet and returns a single UInt32 value.
    # .PARAMETER IPAddress
    #   An IP Address to convert.
    # .INPUTS
    #   System.Net.IPAddress
    # .OUTPUTS
    #   System.UInt32
    # .EXAMPLE
    #   ConvertTo-DecimalIP 1.2.3.4
    #
    #   Converts an IP address to an unsigned 32-bit integer value.
    # .NOTES
    #   Author: Chris Dent
    #
    #   Change log:
    #     06/03/2016 - Chris Dent - Cleaned up code, added tests.
    #     25/11/2010 - Chris Dent - Created.

    [OutputType([System.UInt32])]
    param(
        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $true)]
        [IPAddress]$IPAddress
    )

    process {
        $Bytes = $IPAddress.GetAddressBytes()
        $Decimal = 0;
        for ($i = 0; $i -le 3; $i++) {
            $Decimal += [UInt32]$Bytes[$i] -shl (8 * (3 - $i))
        }

        return [UInt32]$Decimal
    }
}

function ConvertTo-DottedDecimalIP {
    # .SYNOPSIS
    #   Converts either an unsigned 32-bit integer or a dotted binary string to an IP Address.
    # .DESCRIPTION
    #   ConvertTo-DottedDecimalIP uses a regular expression match on the input string to convert to an IP address.
    # .PARAMETER IPAddress
    #   A string representation of an IP address from either UInt32 or dotted binary.
    # .INPUTS
    #   System.String
    # .OUTPUTS
    #   System.Net.IPAddress
    # .EXAMPLE
    #   ConvertTo-DottedDecimalIP 11000000.10101000.00000000.00000001
    #
    #   Convert the binary form back to dotted decimal, resulting in 192.168.0.1.
    # .EXAMPLE
    #   ConvertTo-DottedDecimalIP 3232235521
    #
    #   Convert the decimal form back to dotted decimal, resulting in 192.168.0.1.
    # .NOTES
    #   Author: Chris Dent
    #
    #   Change log:
    #     06/03/2016 - Chris Dent - Cleaned up code, added tests.
    #     25/11/2010 - Chris Dent - Created.

    [OutputType([System.Net.IPAddress])]
    param(
        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $true)]
        [String]$IPAddress
    )

    process {
        switch -regex ($IPAddress) {
            "([01]{8}\.){3}[01]{8}" {
                return [IPAddress]([String]::Join('.', $( $IPAddress -split '\.' | ForEach-Object { [Convert]::ToUInt32($_, 2) } )))
            }
            "\d" {
                $Decimal = [UInt32]$IPAddress
                $DottedDecimalIP = ''
                for ($i = 3; $i -ge 0; $i--) {
                    $Remainder = $Decimal % [Math]::Pow(256, $i)

                    $DottedDecimalIP += ($Decimal - $Remainder) / [Math]::Pow(256, $i)
                    if ($i -gt 0) {
                        $DottedDecimalIP += '.'
                    }

                    $Decimal = $Remainder
                }

                $DottedIP = 3..0 | ForEach-Object {
                    $Remainder = $IPAddress % [Math]::Pow(256, $_)
                    ($IPAddress - $Remainder) / [Math]::Pow(256, $_)
                    $IPAddress = $Remainder
                }

                return [IPAddress]($DottedIP -join '.')
            }
            default {
                $ErrorRecord = New-Object System.Management.Automation.ErrorRecord(
                    (New-Object ArgumentException 'Cannot convert this format.'),
                    'UnrecognisedFormat',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $IPAddress
                )
                Write-Error -ErrorRecord $ErrorRecord
            }
        }
    }
}


function Get-NetworkAddress {
    # .SYNOPSIS
    #   Get the network address for a network range.
    # .DESCRIPTION
    #   Get-NetworkAddress returns the network address for a subnet by performing a bitwise AND operation against the decimal forms of the IP address and subnet mask.
    # .PARAMETER IPAddress
    #   Either a literal IP address, a network range expressed as CIDR notation, or an IP address and subnet mask in a string.
    # .PARAMETER SubnetMask
    #   A subnet mask as an IP address.
    # .INPUTS
    #   System.String
    # .OUTPUTS
    #   System.Net.IPAddress
    # .EXAMPLE
    #   Get-NetworkAddress 192.168.0.243 255.255.255.0
    #
    #   Returns the address 192.168.0.0.
    # .EXAMPLE
    #   Get-NetworkAddress 10.0.9/22
    #
    #   Returns the address 10.0.8.0.
    # .EXAMPLE
    #   Get-NetworkAddress "10.0.23.21 255.255.255.224"
    #
    #   Input values are automatically split into IP address and subnet mask. Returns the address 10.0.23.0.
    # .NOTES
    #   Author: Chris Dent
    #
    #   Change log:
    #     06/03/2016 - Chris Dent - Cleaned up code, added tests.
    #     25/11/2010 - Chris Dent - Created.

    [OutputType([System.Net.IPAddress])]
    param(
        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $true)]
        [String]$IPAddress,

        [Parameter(Position = 2)]
        [String]$SubnetMask
    )

    process {
        try {
            $Network = ConvertToNetwork @psboundparameters
        }
        catch {
            throw $_
        }

        return ConvertTo-DottedDecimalIP ((ConvertTo-DecimalIP $Network.IPAddress) -band (ConvertTo-DecimalIP $Network.SubnetMask))
    }
}


function ConvertTo-MaskLength {
    # .SYNOPSIS
    #   Convert a dotted-decimal subnet mask to a mask length.
    # .DESCRIPTION
    #   A simple count of the number of 1's in a binary string.
    # .PARAMETER SubnetMask
    #   A subnet mask to convert into length.
    # .INPUTS
    #   System.Net.IPAddress
    # .OUTPUTS
    #   System.Int32
    # .EXAMPLE
    #   ConvertTo-MaskLength 255.255.255.0
    #
    #   Returns 24, the length of the mask in bits.
    # .NOTES
    #   Author: Chris Dent
    #
    #   Change log:
    #     06/03/2016 - Chris Dent - Cleaned up code, added tests.
    #     25/11/2010 - Chris Dent - Created.

    [OutputType([System.Int32])]
    param(
        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $true)]
        [Alias("Mask")]
        [IPAddress]$SubnetMask
    )

    process {
        $Bytes = $SubnetMask.GetAddressBytes()
        $MaskBits = ''
        for ($i = 0; $i -lt $Bytes.Count; $i++) {
            $MaskBits += [Convert]::ToString($Bytes[$i], 2)
        }

        return $MaskBits.Replace('0', '').Length
    }
}

function Get-NetworkRange {
    # .SYNOPSIS
    #   Get a list of IP addresses within the specified network.
    # .DESCRIPTION
    #   Get-NetworkRange finds the network and broadcast address as decimal values then starts a counter between the two, returning IPAddress for each.
    # .PARAMETER IPAddress
    #   Either a literal IP address, a network range expressed as CIDR notation, or an IP address and subnet mask in a string.
    # .PARAMETER SubnetMask
    #   A subnet mask as an IP address.
    # .PARAMETER IncludeNetworkAndBroadcast
    #   Include the network and broadcast addresses when generating a network address range.
    # .INPUTS
    #   System.Net.IPAddress
    #   System.String
    # .OUTPUTS
    #   System.Net.IPAddress[]
    # .EXAMPLE
    #   Get-NetworkRange 192.168.0.0 255.255.255.0
    #
    #   Returns all IP addresses in the range 192.168.0.0/24.
    # .EXAMPLE
    #   Get-NetworkRange 10.0.8.0/22
    #
    #   Returns all IP addresses in the range 192.168.0.0 255.255.252.0.
    # .NOTES
    #   Author: Chris Dent
    #
    #   Change log:
    #     07/03/2016 - Chris Dent - Cleaned up code, added tests.
    #     13/10/2011 - Chris Dent - Created.

    [OutputType([System.Net.IPAddress[]])]
    param(
        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $true)]
        [String]$IPAddress,

        [Parameter(Position = 2)]
        [String]$SubnetMask,

        [Switch]$IncludeNetworkAndBroadcast
    )

    process {
        $null = $psboundparameters.Remove('IncludeNetworkAndBroadcast')
        try {
            $Network = ConvertToNetwork @psboundparameters
        }
        catch {
            throw $_
        }

        $DecimalIP = ConvertTo-DecimalIP $Network.IPAddress
        $DecimalMask = ConvertTo-DecimalIP $Network.SubnetMask

        $DecimalNetwork = $DecimalIP -band $DecimalMask
        $DecimalBroadcast = $DecimalIP -bor ((-bnot $DecimalMask) -band [UInt32]::MaxValue)

        if (-not $IncludeNetworkAndBroadcast) {
            $DecimalNetwork += 1
            $DecimalBroadcast -= 1
        }

        for ($i = $DecimalNetwork; $i -le $DecimalBroadcast; $i++) {
            ConvertTo-DottedDecimalIP $i
        }
    }
}

$IPInfo = @()
$NetAddr = @()
$IPAddresses = Get-CimInstance -Namespace root\cimv2 `
    -ClassName Win32_NetworkAdapterConfiguration | `
    Select-Object *, @{name = 'IPv4Address'; expression = {$_.IPAddress -match '\.'}}, @{name = 'IPv4Subnet'; expression = {$_.IPSubnet -match '\.'}} | `
    Where-Object {
   ($_.IPEnabled -eq $True) -and `
        ($_.Description -notmatch 'loop|Hyper') -and `
        ($_.IPv4Address -like '*.*')
}
foreach ($Address in $IPAddresses) {
    $NetAddr = (Get-NetworkAddress -IPAddress ($Address.IPv4Address) -SubnetMask ($Address.IPv4Subnet))
    $IPInfo += $NetAddr
}
#$IPInfo | Format-List

$AccessibleDHCPServers = @()
$DHCPServers = Get-DhcpServerInDC

ForEach ($DHCPServer in $DHCPServers) {
    Try {
        Get-DhcpServerVersion -ComputerName $DHCPServer.DnsName -ErrorAction Stop | Out-Null
        $AccessibleDHCPServers += $DHCPServer
    }
    Catch { }
}

$AllScopes = @()
ForEach ($AccessibleDHCPServer in $AccessibleDHCPServers) {
    ForEach ($Network in $IPInfo) {
        $Scopes = Get-DhcpServerv4Scope -ComputerName $AccessibleDHCPServer.DnsName.Trim() -ScopeId $Network -ErrorAction SilentlyContinue 
        $AllScopes += $Scopes
    }
}

($AllScopes | Select-Object -Property Name, ScopeId, SubnetMask | Sort-Object -Unique | ConvertTo-Csv -Delimiter '|' -NoTypeInformation)[1]
