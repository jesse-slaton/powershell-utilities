function Get-OfficeC2RChannel {
    <#
    .SYNOPSIS
        Outputs the Microsoft 365 Apps (Office Click-to-Run) update channel name.

    .DESCRIPTION
        Reads CDNBaseUrl from HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration (64-bit
        registry view) and outputs the channel name for the GUID at the end of the URL:
        Monthly Enterprise Channel, Current Channel, Current Channel (Preview),
        Semi-Annual Enterprise Channel, Semi-Annual Enterprise Channel (Preview), Beta
        Channel or DevMain Channel. Any other URL is output as
        "Unknown Channel - CDNBaseUrl: <url>". The http and https forms of a URL match alike.

        When the Configuration key does not exist (Office Click-to-Run is not installed) or
        CDNBaseUrl is not set, it writes a non-terminating error and outputs nothing. When
        the registry read itself fails (such as access denied), it writes that error, not a
        "not installed" one, and outputs nothing. Read-only.

        Replaces Scripts/Office/Get-Office365Channel.ps1 (whose function name is kept as an
        alias) and Scripts/Office/GetOffice365Channel-Package.ps1. The package script
        relaunched itself in 64-bit Windows PowerShell to read the 64-bit registry; this
        function reads the 64-bit view directly, so no relaunch is needed.

    .EXAMPLE
        Get-OfficeC2RChannel

        Monthly Enterprise Channel

    .EXAMPLE
        Get-Office365Channel -ErrorAction SilentlyContinue

        Uses the old function name; outputs nothing when Office Click-to-Run is not installed.

    .NOTES
        None. Windows only. Reads HKLM without administrator rights. Part of the OfficeC2R
        module.
    #>
    [CmdletBinding()]
    [Alias('Get-Office365Channel')]
    [OutputType([string])]
    param()

    $channels = @{
        '55336b82-a18d-4dd6-b5f6-9e5095c314a6' = 'Monthly Enterprise Channel'
        '492350f6-3a01-4f97-b9c0-c7c6ddf67d60' = 'Current Channel'
        '64256afe-f5d9-4f86-8936-8840a6a4f5be' = 'Current Channel (Preview)'
        '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114' = 'Semi-Annual Enterprise Channel'
        'b8f9b850-328d-4355-9145-c59439a0c4cf' = 'Semi-Annual Enterprise Channel (Preview)'
        '5440fd1f-7ecb-4221-8110-145efaa6372f' = 'Beta Channel'
        'ea4a4090-de26-49d7-93c1-91bff9e53fc3' = 'DevMain Channel'
    }

    try {
        $config = Get-OfficeC2RConfigurationValue -Name 'CDNBaseUrl' -ErrorAction Stop
    }
    catch {
        $PSCmdlet.WriteError($_)
        return
    }
    if ($null -eq $config) {
        Write-Error -Message 'Office Click-to-Run configuration is not found. Office may not be installed.' -Category ObjectNotFound
        return
    }

    $url = [string]$config['CDNBaseUrl']
    if (-not $url) {
        Write-Error -Message 'The CDNBaseUrl value is not set. Unable to determine the Office update channel.' -Category ObjectNotFound
        return
    }

    if ($url -match '^https?://officecdn\.microsoft\.com/pr/(?<id>[0-9a-fA-F-]{36})/?$' -and $channels.ContainsKey($Matches['id'])) {
        $channels[$Matches['id']]
    }
    else {
        "Unknown Channel - CDNBaseUrl: $url"
    }
}
