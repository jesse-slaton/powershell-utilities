# Device Guard helpers. Every CIM call in the Device Guard functions goes through these
# wrappers so tests can mock them (Win32_DeviceGuard exists only on Windows 10 and later).

function Get-DeviceGuardInstance {
    <#
    .SYNOPSIS
        Reads the Win32_DeviceGuard instance of this computer.

    .DESCRIPTION
        Returns the Win32_DeviceGuard CIM instance from the
        root\Microsoft\Windows\DeviceGuard namespace. Throws if the class cannot be read.
        Private to SecurityPosture.

    .EXAMPLE
        $deviceGuard = Get-DeviceGuardInstance

    .NOTES
        Windows 10 or later (Win32_DeviceGuard). Read-only.
    #>
    [CmdletBinding()]
    param()

    Get-CimInstance -ClassName Win32_DeviceGuard -Namespace 'root\Microsoft\Windows\DeviceGuard' -ErrorAction Stop
}

function Get-SecurityPostureOSVersion {
    <#
    .SYNOPSIS
        Returns the operating system version of this computer as a System.Version.

    .DESCRIPTION
        Reads Version from Win32_OperatingSystem and converts it to System.Version.
        Throws if the class cannot be read. Private to SecurityPosture.

    .EXAMPLE
        if ((Get-SecurityPostureOSVersion) -lt [version]'10.0') { 'too old' }

    .NOTES
        Windows only (CIM). Read-only.
    #>
    [CmdletBinding()]
    [OutputType([version])]
    param()

    [version](Get-CimInstance -ClassName Win32_OperatingSystem -Namespace 'root\cimv2' -ErrorAction Stop).Version
}

function Get-DeviceGuardPropertyTable {
    <#
    .SYNOPSIS
        Returns the Device Guard security property names keyed by their numeric value.

    .DESCRIPTION
        Returns a hashtable mapping each value of AvailableSecurityProperties and
        RequiredSecurityProperties to its name: 0 None, 1 Hypervisor, 2 Secure Boot,
        3 DMA Protection, 4 Secure Memory Overwrite, 5 NX Protections, 6 SMM Mitigations,
        7 MBEC/GMET, 8 APIC Virtualization (the values Microsoft documents for
        Win32_DeviceGuard; 8 is documented for AvailableSecurityProperties only).
        Private to SecurityPosture.

    .EXAMPLE
        (Get-DeviceGuardPropertyTable)[[uint32]2]

        Returns 'Secure Boot'.

    .NOTES
        None.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    # A hashtable, not [ordered]: an OrderedDictionary indexed with a number can pick the
    # positional indexer instead of the key.
    @{
        [uint32]0 = 'None'
        [uint32]1 = 'Hypervisor'
        [uint32]2 = 'Secure Boot'
        [uint32]3 = 'DMA Protection'
        [uint32]4 = 'Secure Memory Overwrite'
        [uint32]5 = 'NX Protections'
        [uint32]6 = 'SMM Mitigations'
        [uint32]7 = 'MBEC/GMET'
        [uint32]8 = 'APIC Virtualization'
    }
}

function ConvertTo-DeviceGuardPropertyName {
    <#
    .SYNOPSIS
        Translates Device Guard security property values to their names.

    .DESCRIPTION
        Returns one name per input value, in input order, using Get-DeviceGuardPropertyTable.
        A value with no name in the table is returned as 'Unknown (<value>)'. Returns
        nothing for an empty or null input. Private to SecurityPosture.

    .PARAMETER Value
        The numeric property values, as read from AvailableSecurityProperties or
        RequiredSecurityProperties.

    .EXAMPLE
        ConvertTo-DeviceGuardPropertyName -Value 1, 2

        Returns 'Hypervisor' and 'Secure Boot'.

    .EXAMPLE
        ConvertTo-DeviceGuardPropertyName -Value 9

        Returns 'Unknown (9)'.

    .NOTES
        None.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Value
    )

    $table = Get-DeviceGuardPropertyTable
    foreach ($item in @($Value | Where-Object { $null -ne $_ })) {
        $key = [uint32]$item
        if ($table.ContainsKey($key)) { $table[$key] } else { "Unknown ($key)" }
    }
}
