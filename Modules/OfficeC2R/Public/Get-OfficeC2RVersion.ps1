function Get-OfficeC2RVersion {
    <#
    .SYNOPSIS
        Looks up the installed Office Click-to-Run build in an online version list.

    .DESCRIPTION
        Reads VersionToReport from HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration
        (64-bit registry view), downloads the full Office version list as JSON from
        https://functions.office365versions.com/api/getjson?name=all, and outputs one object
        per list entry whose fullBuild equals the installed version, with the properties
        Version, Channel, Build ([version]), ReleaseDate and EndOfSupportDate. The two dates
        are [datetime] when the list holds a date in either the 'yyyy MMM dd' form or a
        standard form (such as ISO 8601), whichever PowerShell edition runs it; any other
        text (such as an empty or "N/A" end of support) is output unchanged. Outputs nothing
        when no entry matches.

        When the Configuration key does not exist or VersionToReport is not set, it writes
        a non-terminating error and downloads nothing. When the registry read itself fails
        (such as access denied), it writes that error, not a "not installed" one, and
        downloads nothing. A failed download is a terminating
        error. Read-only on this computer.

        Replaces the logic of Scripts/Office/GetOfficeVersion-Package.ps1, which is now a
        thin wrapper that saves this output as CLIXML.

    .EXAMPLE
        Get-OfficeC2RVersion

        Outputs the version list entries for the installed build, one per channel.

    .EXAMPLE
        Get-OfficeC2RVersion | Select-Object -First 1 -ExpandProperty Channel

        Outputs the channel name of the first matching entry.

    .NOTES
        Requires internet access to functions.office365versions.com (a third-party site)
        and Office Click-to-Run installed. Windows only. Reads HKLM without administrator
        rights. Part of the OfficeC2R module.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    function ConvertTo-OfficeC2RDate {
        # ConvertFrom-Json on PowerShell 7 already turns ISO 8601 strings into [datetime];
        # Windows PowerShell 5.1 leaves them as strings. Normalize both to [datetime].
        param($Value)
        if ($null -eq $Value -or $Value -is [datetime]) {
            return $Value
        }
        $text = [string]$Value
        $invariant = [System.Globalization.CultureInfo]::InvariantCulture
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParseExact($text, 'yyyy MMM dd', $invariant, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
            return $parsed
        }
        if ([datetime]::TryParse($text, $invariant, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) {
            return $parsed
        }
        $text
    }

    try {
        $config = Get-OfficeC2RConfigurationValue -Name 'VersionToReport' -ErrorAction Stop
    }
    catch {
        $PSCmdlet.WriteError($_)
        return
    }
    if ($null -eq $config) {
        Write-Error -Message 'Office Click-to-Run configuration is not found. Office may not be installed.' -Category ObjectNotFound
        return
    }
    $installed = [string]$config['VersionToReport'] -as [version]
    if ($null -eq $installed) {
        Write-Error -Message "The VersionToReport value is not set or is not a version: '$($config['VersionToReport'])'." -Category InvalidData
        return
    }

    $response = Invoke-WebRequest -Uri 'https://functions.office365versions.com/api/getjson?name=all' -UseBasicParsing -ErrorAction Stop
    foreach ($entry in @(($response.Content | ConvertFrom-Json).data)) {
        if (([string]$entry.fullBuild -as [version]) -ne $installed) {
            continue
        }
        [pscustomobject]@{
            Version          = $entry.version
            Channel          = $entry.channel
            Build            = [string]$entry.build -as [version]
            ReleaseDate      = ConvertTo-OfficeC2RDate -Value $entry.releaseDate
            EndOfSupportDate = ConvertTo-OfficeC2RDate -Value $entry.endOfSupportDate
        }
    }
}
