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
    } else {
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
    } else {
        $MaskLength = 0
        if ([Int32]::TryParse($SubnetMask, [Ref]$MaskLength)) {
            if ($MaskLength -ge 0 -and $MaskLength -le 32) {
                $Network.SubnetMask = [IPAddress]$Script:ValidSubnetMaskValues[$MaskLength]
                $Network.MaskLength = $MaskLength
            } else {
                $ErrorRecord = New-Object System.Management.Automation.ErrorRecord(
                    (New-Object ArgumentException 'Mask length out of range (expecting 0 to 32).'),
                    'InvalidMaskLength',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $SubnetMask
                )
                throw $ErrorRecord
            }
        } else {
            while ($SubnetMask.Split('.').Count -lt 4) {
                $SubnetMask += '.0'
            }
            $MaskLength = $Script:ValidSubnetMaskValues.IndexOf($SubnetMask)

            if ($MaskLength -ge 0) {
                $Network.SubnetMask = [IPAddress]$SubnetMask
                $Network.MaskLength = $MaskLength
            } else {
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

function ConvertFrom-HexIP {
    # .SYNOPSIS
    #   Converts a hexadecimal IP address into a dotted decimal string.
    # .DESCRIPTION
    #   ConvertFrom-HexIP takes a hexadecimal string and returns a dotted decimal IP address. An intermediate call is made to ConvertTo-DottedDecimalIP.
    # .PARAMETER IPAddress
    #   An IP Address to convert.
    # .INPUTS
    #   System.String
    # .OUTPUTS
    #   System.Net.IPAddress
    # .EXAMPLE
    #   ConvertFrom-HexIP c0a80001
    #
    #   Returns the IP address 192.168.0.1.
    # .NOTES
    #   Author: Chris Dent
    #
    #   Change log:
    #     06/03/2016 - Chris Dent - Cleaned up code, added tests.
    #     13/10/2011 - Chris Dent - Created.

    [OutputType([System.Net.IPAddress])]
    param(
        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $true)]
        [ValidatePattern('^(0x)?[0-9a-f]{8}$')]
        [String]$IPAddress
    )

    process {
        return ConvertTo-DottedDecimalIP ([Convert]::ToUInt32($IPAddress, 16))
    }
}

function ConvertTo-BinaryIP {
    # .SYNOPSIS
    #   Converts a Decimal IP address into a binary format.
    # .DESCRIPTION
    #   ConvertTo-BinaryIP uses System.Convert to switch between decimal and binary format. The output from this function is dotted binary.
    # .PARAMETER IPAddress
    #   An IP Address to convert.
    # .INPUTS
    #   System.Net.IPAddress
    # .OUTPUTS
    #   System.String
    # .EXAMPLE
    #   ConvertTo-BinaryIP 1.2.3.4
    #
    #   Convert an IP address to a binary format.
    # .NOTES
    #   Author: Chris Dent
    #
    #   Change log:
    #     06/03/2016 - Chris Dent - Cleaned up code, added tests.
    #     25/11/2010 - Chris Dent - Created.

    [OutputType([System.String])]
    param(
        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $true)]
        [IPAddress]$IPAddress
    )

    process {
        $Bytes = $IPAddress.GetAddressBytes()
        $Binary = ''
        for ($i = 0; $i -lt $Bytes.Count; $i++) {
            $Binary += [Convert]::ToString($Bytes[$i], 2).PadLeft(8, '0')
            if ($i -lt ($Bytes.Count - 1)) {
                $Binary += '.'
            }
        }

        return $Binary
    }
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

function ConvertTo-HexIP {
    # .SYNOPSIS
    #   Convert a dotted decimal IP address into a hexadecimal string.
    # .DESCRIPTION
    #   ConvertTo-HexIP takes a dotted decimal IP and returns a single hexadecimal string value.
    # .PARAMETER IPAddress
    #   An IP Address to convert.
    # .INPUTS
    #    System.Net.IPAddress
    # .OUTPUTS
    #    System.String
    # .EXAMPLE
    #   ConvertTo-HexIP 192.168.0.1
    #
    #   Returns the hexadecimal string c0a80001.
    # .NOTES
    #   Author: Chris Dent
    #
    #   Change log:
    #     06/03/2016 - Chris Dent - Cleaned up code, added tests.
    #     13/10/2011 - Chris Dent - Refactored.

    [OutputType([System.String])]
    param(
        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $true)]
        [IPAddress]$IPAddress
    )

    process {
        $Bytes = $IPAddress.GetAddressBytes()
        $Hex = ''
        for ($i = 0; $i -lt $Bytes.Count; $i++) {
            $Hex += '{0:x2}' -f $Bytes[$i]
        }

        return $Hex
    }
}

function ConvertTo-Mask {
    # .SYNOPSIS
    #   Convert a mask length to a dotted-decimal subnet mask.
    # .DESCRIPTION
    #   ConvertTo-Mask returns a subnet mask in dotted decimal format from an integer value ranging between 0 and 32.
    #
    #   ConvertTo-Mask creates a binary string from the length, converts the string to an unsigned 32-bit integer then calls ConvertTo-DottedDecimalIP to complete the operation.
    # .PARAMETER MaskLength
    #   The number of bits which must be masked.
    # .INPUTS
    #   System.Int32
    # .OUTPUTS
    #   System.Net.IPAddress
    # .EXAMPLE
    #   ConvertTo-Mask 24
    #
    #   Returns the dotted-decimal form of the mask, 255.255.255.0.
    # .NOTES
    #   Author: Chris Dent
    #
    #   Change log:
    #     06/03/2016 - Chris Dent - Cleaned up code, added tests.
    #     25/11/2010 - Chris Dent - Created.

    [OutputType([System.Net.IPAddress])]
    param(
        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $true)]
        [Alias('Length')]
        [ValidateRange(0, 32)]
        [Byte]$MaskLength
    )

    process {
        $Binary = ("1" * $MaskLength).PadRight(32, "0")
        $Decimal = [Convert]::ToUInt32($Binary, 2)

        return ConvertTo-DottedDecimalIP $Decimal
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

function ConvertTo-Subnet {
    # .SYNOPSIS
    #   Convert a start and end IP address to the closest matching subnet.
    # .DESCRIPTION
    #   ConvertTo-Subnet attempts to convert a starting and ending IP address from a range to the closest subnet.
    # .PARAMETER End
    #   The last IP address from a range.
    # .PARAMETER IPAddress
    #    Any IP address in the subnet.
    # .PARAMETER Start
    #   The first IP address from a range.
    # .PARAMETER SubnetMask
    #    A subnet mask.
    # .INPUTS
    #   System.Net.IPAddress
    # .OUTPUTS
    #   Indented.Net.IP.Subnet
    # .EXAMPLE
    #   ConvertTo-Subnet -Start 0.0.0.0 -End 255.255.255.255
    # .EXAMPLE
    #   ConvertTo-Subnet -Start 192.168.0.1 -End 192.168.0.129
    # .EXAMPLE
    #   ConvertTo-Subnet 10.0.0.23/24
    # .EXAMPLE
    #   ConvertTo-Subnet 10.0.0.23 255.255.255.0
    # .NOTES
    #   Author: Chris Dent
    #
    #   Change log:
    #     06/03/2016 - Chris Dent - Cleaned up code, added tests.
    #     14/05/2014 - Chris Dent - Created.

    [CmdletBinding(DefaultParameterSetName = 'FromIPAndMask')]
    [OutputType([System.Management.Automation.PSObject])]
    param(
        [Parameter(Mandatory = $true, Position = 1, ParameterSetName = 'FromIPAndMask')]
        [String]$IPAddress,

        [Parameter(Position = 2, ParameterSetName = 'FromIPAndMask')]
        [String]$SubnetMask,

        [Parameter(Mandatory = $true, ParameterSetName = 'FromStartAndEnd')]
        [IPAddress]$Start,

        [Parameter(Mandatory = $true, ParameterSetName = 'FromStartAndEnd')]
        [IPAddress]$End
    )

    process {
        if ($pscmdlet.ParameterSetName -eq 'FromIPAndMask') {
            try {
                $Network = ConvertToNetwork @psboundparameters
            } catch {
                $pscmdlet.ThrowTerminatingError($_)
            }
        } elseif ($pscmdlet.ParameterSetName -eq 'FromStartAndEnd') {
            if ($Start -eq $End) {
                $MaskLength = 32
            } else {
                $DecimalStart = ConvertTo-DecimalIP $Start
                $DecimalEnd = ConvertTo-DecimalIP $End

                if ($DecimalEnd -lt $DecimalStart) {
                    $Start = $End
                }

                # Find the point the binary representation of each IP address diverges
                $i = 32
                do {
                    $i--
                } until (($DecimalStart -band ([UInt32]1 -shl $i)) -ne ($DecimalEnd -band ([UInt32]1 -shl $i)))

                $MaskLength = 32 - $i - 1
            }

            try {
                $Network = ConvertToNetwork "$Start/$MaskLength"
            } catch {
                $pscmdlet.ThrowTerminatingError($_)
            }
        }

        $HostAddresses = [Math]::Pow(2, (32 - $Network.MaskLength)) - 2
        if ($HostAddresses -lt 0) { $HostAddresses = 0 }

        $Subnet = [PSCustomObject]@{
            NetworkAddress   = Get-NetworkAddress $Network.ToString()
            BroadcastAddress = Get-BroadcastAddress $Network.ToString()
            SubnetMask       = $Network.SubnetMask
            MaskLength       = $Network.MaskLength
            HostAddresses    = $HostAddresses
        } | Add-Member -TypeName 'Indented.Net.IP.Subnet' -PassThru

        $Subnet | Add-Member ToString -MemberType ScriptMethod -Force -Value {
            return '{0}/{1}' -f $this.NetworkAddress, $this.MaskLength
        }

        $Subnet
    }
}


function Get-BroadcastAddress {
    # .SYNOPSIS
    #   Get the broadcast address for a network range.
    # .DESCRIPTION
    #   Get-BroadcastAddress returns the broadcast address for a subnet by performing a bitwise AND operation against the decimal forms of the IP address and inverted subnet mask.
    # .PARAMETER IPAddress
    #   Either a literal IP address, a network range expressed as CIDR notation, or an IP address and subnet mask in a string.
    # .PARAMETER SubnetMask
    #   A subnet mask as an IP address.
    # .INPUTS
    #   System.String
    # .OUTPUTS
    #   System.Net.IPAddress
    # .EXAMPLE
    #   Get-BroadcastAddress 192.168.0.243 255.255.255.0
    #
    #   Returns the address 192.168.0.255.
    # .EXAMPLE
    #   Get-BroadcastAddress 10.0.9/22
    #
    #   Returns the address 10.0.11.255.
    # .EXAMPLE
    #   Get-BroadcastAddress 0/0
    #
    #   Returns the address 255.255.255.255.
    # .EXAMPLE
    #   Get-BroadcastAddress "10.0.0.42 255.255.255.252"
    #
    #   Input values are automatically split into IP address and subnet mask. Returns the address 10.0.0.43.
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
        } catch {
            throw $_
        }

        return ConvertTo-DottedDecimalIP ((ConvertTo-DecimalIP $Network.IPAddress) -bor ((-bnot (ConvertTo-DecimalIP $Network.SubnetMask)) -band [UInt32]::MaxValue))
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
        } catch {
            throw $_
        }

        return ConvertTo-DottedDecimalIP ((ConvertTo-DecimalIP $Network.IPAddress) -band (ConvertTo-DecimalIP $Network.SubnetMask))
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
        } catch {
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

function Get-NetworkSummary {
    # .SYNOPSIS
    #   Generates a summary describing several properties of a network range
    # .DESCRIPTION
    #   Get-NetworkSummary uses many of the IP conversion CmdLets to provide a summary of a network range from any IP address in the range and a subnet mask.
    # .PARAMETER IPAddress
    #   Either a literal IP address, a network range expressed as CIDR notation, or an IP address and subnet mask in a string.
    # .PARAMETER SubnetMask
    #   A subnet mask as an IP address.
    # .INPUTS
    #   System.Net.IPAddress
    #   System.String
    # .OUTPUTS
    #   Indented.Net.IP.NetworkSummary (System.Management.Automation.PSObject)
    # .EXAMPLE
    #   Get-NetworkSummary 192.168.0.1 255.255.255.0
    # .EXAMPLE
    #   Get-NetworkSummary 10.0.9.43/22
    # .EXAMPLE
    #   Get-NetworkSummary 0/0
    # .NOTES
    #   Author: Chris Dent
    #
    #   Change log:
    #     07/03/2016 - Chris Dent - Cleaned up code, added tests.
    #     25/11/2010 - Chris Dent - Created.

    [OutputType([System.Management.Automation.PSObject])]
    param(
        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $true)]
        [String]$IPAddress,

        [Parameter(Position = 2)]
        [String]$SubnetMask
    )

    process {
        try {
            $Network = ConvertToNetwork @psboundparameters
        } catch {
            throw $_
        }

        $DecimalIP = ConvertTo-DecimalIP $Network.IPAddress
        $DecimalMask = ConvertTo-DecimalIP $Network.SubnetMask
        $DecimalNetwork =  $DecimalIP -band $DecimalMask
        $DecimalBroadcast = $DecimalIP -bor ((-bnot $DecimalMask) -band [UInt32]::MaxValue)

        $NetworkSummary = [PSCustomObject]@{
            NetworkAddress    = (ConvertTo-DottedDecimalIP $DecimalNetwork);
            NetworkDecimal    = $DecimalNetwork
            BroadcastAddress  = (ConvertTo-DottedDecimalIP $DecimalBroadcast);
            BroadcastDecimal  = $DecimalBroadcast
            Mask              = $Network.SubnetMask;
            MaskLength        = (ConvertTo-MaskLength $Network.SubnetMask);
            MaskHexadecimal   = (ConvertTo-HexIP $Network.SubnetMask);
            CIDRNotation      = ""
            HostRange         = "";
            NumberOfAddresses = ($DecimalBroadcast - $DecimalNetwork + 1)
            NumberOfHosts     = ($DecimalBroadcast - $DecimalNetwork - 1);
            Class             = "";
            IsPrivate         = $false
        } | Add-Member -TypeName 'Indented.Net.IP.NetworkSummary' -PassThru

        $NetworkSummary.CIDRNotation = '{0}/{1}' -f $NetworkSummary.NetworkAddress, $NetworkSummary.MaskLength

        if ($NetworkSummary.NumberOfHosts -lt 0) {
            $NetworkSummary.NumberOfHosts = 0
        }
        if ($NetworkSummary.MaskLength -lt 31) {
            $NetworkSummary.HostRange = '{0} - {1}' -f (ConvertTo-DottedDecimalIP ($DecimalNetwork + 1)), (ConvertTo-DottedDecimalIP ($DecimalBroadcast - 1))
        }

        switch -regex (ConvertTo-BinaryIP $Network.IPAddress) {
            "^1111"              { $NetworkSummary.Class = "E"; break }
            "^1110"              { $NetworkSummary.Class = "D"; break }
            "^11000000.10101000" { $NetworkSummary.Class = "C"; if ($NetworkSummary.MaskLength -ge 16) { $NetworkSummary.IsPrivate = $true }; break }
            "^110"               { $NetworkSummary.Class = "C" }
            "^10101100.0001"     { $NetworkSummary.Class = "B"; if ($NetworkSummary.MaskLength -ge 12) { $NetworkSummary.IsPrivate = $true }; break }
            "^10"                { $NetworkSummary.Class = "B"; break }
            "^00001010"          { $NetworkSummary.Class = "A"; if ($NetworkSummary.MaskLength -ge 8) { $NetworkSummary.IsPrivate = $true}; break }
            "^0"                 { $NetworkSummary.Class = "A"; break }
        }

        return $NetworkSummary
    }
}

function Get-Subnet {
    # .SYNOPSIS
    #   Get a list of subnets of a given size within a defined supernet.
    # .DESCRIPTION
    #   Generates a list of subnets for a given network range using either the address class or a user-specified value.
    # .PARAMETER IPAddress
    #   Any address in the super-net range. Either a literal IP address, a network range expressed as CIDR notation, or an IP address and subnet mask in a string.
    # .PARAMETER SubnetMask
    #   The subnet mask of the network to split. Mandatory if the subnet mask is not included in the IPAddress parameter.
    # .PARAMETER NewSubnetMask
    #   Split the existing network described by the IPAddress and subnet mask using this mask.
    # .INPUTS
    #   System.String
    # .OUTPUTS
    #   Indented.Net.IP.Subnet
    # .EXAMPLE
    #   Get-Subnet 10.0.0.0 255.255.255.0 -NewSubnetMask 255.255.255.192
    #
    #   Four /26 networks are returned.
    # .EXAMPLE
    #   Get-Subnet 0/22 -NewSubnetMask 24
    #
    #   64 /24 networks are returned.
    # .NOTES
    #   Author: Chris Dent
    #
    #   Change log:
    #     07/03/2016 - Chris Dent - Cleaned up code, added tests.
    #     12/12/2015 - Chris Dent - Redesigned.
    #     13/10/2011 - Chris Dent - Created.

    [OutputType([System.Management.Automation.PSObject])]
    param(
        [Parameter(Mandatory = $true, Position = 1)]
        [String]$IPAddress,

        [Parameter(Position = 2)]
        [String]$SubnetMask,

        [Parameter(Mandatory = $true)]
        [String]$NewSubnetMask
    )

    $null = $psboundparameters.Remove('NewSubnetMask')
    try {
        $Network = ConvertToNetwork @psboundparameters
    } catch {
        throw $_
    }

    try {
        $NewNetwork = ConvertToNetwork "0/$NewSubnetMask"
    } catch {
        throw $_
    }

    if ($Network.MaskLength -gt $NewNetwork.MaskLength) {
        $ErrorRecord = New-Object System.Management.Automation.ErrorRecord(
            (New-Object ArgumentException 'The subnet mask of the new network is shorter (masks fewer addresses) than the subnet mask of the existing network.'),
            'NewSubnetMaskTooShort',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $NewNetwork.MaskLength
        )
        throw $ErrorRecord
    }

    $NumberOfNets = [Math]::Pow(2, ($NewNetwork.MaskLength - $Network.MaskLength))
    $NumberOfAddresses = [Math]::Pow(2, (32 - $NewNetwork.MaskLength))

    $DecimalAddress = ConvertTo-DecimalIP (Get-NetworkAddress $Network.ToString())
    for ($i = 0; $i -lt $NumberOfNets; $i++) {
        $NetworkAddress = ConvertTo-DottedDecimalIP $DecimalAddress

        ConvertTo-Subnet "$NetworkAddress/$($NewNetwork.MaskLength)"

        $DecimalAddress += $NumberOfAddresses
    }
}

function Test-SubnetMember {
    # .SYNOPSIS
    #   Tests an IP address to determine if it falls within IP address range.
    # .DESCRIPTION
    #   Test-SubnetMember attempts to determine whether or not an address or range falls within another range. The network and broadcast address are calculated the converted to decimal then compared to the decimal form of the submitted address.
    # .PARAMETER ObjectIPAddress
    #   A representation of the object, the network to test against. Either a literal IP address, a network range expressed as CIDR notation, or an IP address and subnet mask in a string.
    # .PARAMETER ObjectSubnetMask
    #   A subnet mask as an IP address.
    # .PARAMETER SubjectIPAddress
    #   A representation of the subject, the network to be tested. Either a literal IP address, a network range expressed as CIDR notation, or an IP address and subnet mask in a string.
    # .PARAMETER SubjectSubnetMask
    #   A subnet mask as an IP address.
    # .INPUTS
    #    System.String
    # .OUTPUTS
    #    System.Boolean
    # .EXAMPLE
    #   Test-SubnetMember -SubjectIPAddress 10.0.0.0/24 -ObjectIPAddress 10.0.0.0/16
    #
    #   Returns true as the subject network can be contained within the object network.
    # .EXAMPLE
    #   Test-SubnetMember -SubjectIPAddress 192.168.0.0/16 -ObjectIPAddress 192.168.0.0/24
    #
    #   Returns false as the subject network is larger the object network.
    # .EXAMPLE
    #   Test-SubnetMember -SubjectIPAddress 10.2.3.4/32 -ObjectIPAddress 10.0.0.0/8
    #
    #   Returns true as the subject IP address is within the object network.
    # .EXAMPLE
    #   Test-SubnetMember -SubjectIPAddress 255.255.255.255 -ObjectIPAddress 0/0
    #
    #   Returns true as the subject IP address is the last in the object network range.
    # .NOTES
    #   Author: Chris Dent
    #
    #   Change log:
    #     07/03/2016 - Chris Dent - Cleaned up code, added tests.
    #     12/08/2013 - Chris Dent - Created.

    [OutputType([System.Boolean])]
    param(
        [Parameter(Mandatory = $true, Position = 1)]
        [String]$SubjectIPAddress,

        [Parameter(Mandatory = $true, Position = 2)]
        [String]$ObjectIPAddress,

        [Parameter()]
        [String]$SubjectSubnetMask,

        [Parameter()]
        [String]$ObjectSubnetMask
    )

    try {
        $SubjectNetwork = ConvertToNetwork $SubjectIPAddress $SubjectSubnetMask
    } catch {
        throw $_
    }

    try {
        $ObjectNetwork = ConvertToNetwork $ObjectIPAddress $ObjectSubnetMask
    } catch {
        throw $_
    }

    # A simple check, if the mask is shorter (larger network) then it won't be a subnet of the object anyway.
    if ($SubjectNetwork.MaskLength -lt $ObjectNetwork.MaskLength) {
        return $false
    }

    $SubjectDecimalIP = ConvertTo-DecimalIP $SubjectNetwork.IPAddress
    $ObjectDecimalNetwork = ConvertTo-DecimalIP (Get-NetworkAddress $ObjectNetwork)
    $ObjectDecimalBroadcast = ConvertTo-DecimalIP (Get-BroadcastAddress $ObjectNetwork)

    # If the mask is longer (smaller network), then the decimal form of the address must be between the
    # network and broadcast address of the object (the network we test against).
    if ($SubjectDecimalIP -ge $ObjectDecimalNetwork -and $SubjectDecimalIP -le $ObjectDecimalBroadcast) {
        return $true
    } else {
        return $false
    }
}

