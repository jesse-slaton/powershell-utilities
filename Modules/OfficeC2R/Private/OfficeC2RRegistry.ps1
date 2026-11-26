# Every registry access in OfficeC2R goes through this file so tests can mock it (the
# registry exists only on Windows). It opens the 64-bit view of HKLM, so the result is the
# same from 32-bit and 64-bit PowerShell on 64-bit Windows.

function Get-OfficeC2RConfigurationValue {
    <#
    .SYNOPSIS
        Reads values from the Office Click-to-Run Configuration registry key.

    .DESCRIPTION
        Opens HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration in the 64-bit
        registry view and returns a hashtable with one entry per requested value name; a
        value that is not set is $null in the hashtable. Returns $null when the key does
        not exist (Office Click-to-Run is not installed). Any other failure, such as access
        to the key being denied, is a terminating error, so a caller can catch it instead of
        mistaking it for a missing key. Read-only. Private to OfficeC2R.

    .PARAMETER Name
        One or more value names to read, such as CDNBaseUrl, Platform or VersionToReport.

    .EXAMPLE
        (Get-OfficeC2RConfigurationValue -Name CDNBaseUrl)['CDNBaseUrl']

    .EXAMPLE
        Get-OfficeC2RConfigurationValue -Name Platform, VersionToReport

    .NOTES
        Windows only. Reads HKLM without administrator rights.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Name
    )

    # A .NET exception (such as a SecurityException from OpenSubKey) is only
    # statement-terminating by default: the caller would carry on with $null and report
    # a missing key. Stop makes it terminating so it reaches the caller's catch.
    $ErrorActionPreference = 'Stop'
    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
    try {
        $key = $baseKey.OpenSubKey('SOFTWARE\Microsoft\Office\ClickToRun\Configuration')
        if ($null -eq $key) {
            return $null
        }
        try {
            $values = @{}
            foreach ($valueName in $Name) {
                $values[$valueName] = $key.GetValue($valueName)
            }
            $values
        }
        finally {
            $key.Close()
        }
    }
    finally {
        $baseKey.Close()
    }
}
