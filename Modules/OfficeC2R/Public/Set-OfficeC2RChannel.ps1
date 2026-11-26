function Set-OfficeC2RChannel {
    <#
    .SYNOPSIS
        Switches Office Click-to-Run to another update channel and forces an update.

    .DESCRIPTION
        Checks that OfficeC2RClient.exe exists, then sets UpdateChannel under
        HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration (64-bit registry view) to
        the CDN URL of the channel. It then runs OfficeC2RClient.exe with
        "/update user displaylevel=false forceappshutdown=true", which closes open Office
        apps without asking, waits for it, and outputs an object with Channel,
        UpdateChannel (the URL) and ExitCode.

        Exit code 0 is success. 1601 (update already in progress), 1704 (an installation is
        suspended) and 3010 (reboot required) also write a warning; any other code writes a
        non-terminating error. It writes an error and outputs nothing, without running
        OfficeC2RClient.exe, when OfficeC2RClient.exe is missing or the registry write fails
        (such as without administrator rights); and it writes an error and outputs nothing
        when OfficeC2RClient.exe does not start. Supports -WhatIf and -Confirm.

        Replaces Scripts/Office/SwitchOfficeC2RChannel.ps1, with its channel URLs corrected:
        the script sent MonthlyEnterprise to Current Channel (Preview), SemiAnnual to
        Semi-Annual Enterprise Channel (Preview) and Beta to Semi-Annual Enterprise Channel.
        The script's empty HKCU policy keys, unused CDN connectivity check and
        updatebranch value (not a setting Office documents under that key) are dropped.
        The script ended with the client's exit code; a caller that relies on it can run:

            $r = Set-OfficeC2RChannel -OfficeChannel <channel>; if ($r) { exit $r.ExitCode }; exit 1

        The shorter "exit (Set-OfficeC2RChannel -OfficeChannel <channel>).ExitCode" exits 0
        when the function outputs nothing, so it hides the failures above.

    .PARAMETER OfficeChannel
        The channel to switch to: Current, MonthlyEnterprise, SemiAnnual (Semi-Annual
        Enterprise Channel) or Beta. Default SemiAnnual. Each name selects only the CDN URL
        written to UpdateChannel; Beta is the Beta Channel URL, not an Office branch value.

    .EXAMPLE
        Set-OfficeC2RChannel -OfficeChannel Current

        Switches Office to Current Channel and runs an update.

    .EXAMPLE
        Set-OfficeC2RChannel -OfficeChannel MonthlyEnterprise -WhatIf

        Shows what would change without writing the registry or starting an update.

    .NOTES
        Requires administrator rights. Windows only. Closes running Office apps. Part of the
        OfficeC2R module.

        An Office update policy overrides this function. When Group Policy or Cloud Update
        sets UpdatePath or UpdateBranch, for example under
        HKLM\SOFTWARE\Policies\Microsoft\office\16.0\Common\officeupdate, Office keeps
        the policy channel even though the output names the new one. Check
        Get-OfficeC2RChannel after the next update.

    .LINK
        https://learn.microsoft.com/microsoft-365-apps/updates/overview-update-channels
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [ValidateSet('Current', 'MonthlyEnterprise', 'SemiAnnual', 'Beta')]
        [string]$OfficeChannel = 'SemiAnnual'
    )

    $channelUrls = @{
        Current           = 'http://officecdn.microsoft.com/pr/492350f6-3a01-4f97-b9c0-c7c6ddf67d60'
        MonthlyEnterprise = 'http://officecdn.microsoft.com/pr/55336b82-a18d-4dd6-b5f6-9e5095c314a6'
        SemiAnnual        = 'http://officecdn.microsoft.com/pr/7ffbc6bf-bc32-4f92-8982-f9dd17fd3114'
        Beta              = 'http://officecdn.microsoft.com/pr/5440fd1f-7ecb-4221-8110-145efaa6372f'
    }
    $channelUrl = $channelUrls[$OfficeChannel]
    $client = 'C:\Program Files\Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe'

    if (-not (Test-Path -LiteralPath $client -PathType Leaf)) {
        Write-Error -Message "OfficeC2RClient.exe not found at $client. Office Click-to-Run may not be installed." -Category ObjectNotFound
        return
    }

    if (-not $PSCmdlet.ShouldProcess('Office Click-to-Run', "Switch the update channel to $OfficeChannel and run an update that closes Office apps")) {
        return
    }

    try {
        Write-OfficeC2RConfigurationValue -Name 'UpdateChannel' -Value $channelUrl -ErrorAction Stop
    }
    catch {
        Write-Error -Message "Unable to set UpdateChannel, so the update was not run: $($_.Exception.Message)" -Exception $_.Exception -Category WriteError
        return
    }

    $process = Start-Process -FilePath $client -ArgumentList '/update user displaylevel=false forceappshutdown=true' -Wait -PassThru
    if ($null -eq $process) {
        Write-Error -Message "OfficeC2RClient.exe did not start, so no update ran. UpdateChannel is already set to $OfficeChannel." -Category InvalidResult
        return
    }
    $exitCode = [int]$process.ExitCode

    switch ($exitCode) {
        0 { Write-Verbose 'Office Click-to-Run update completed successfully.' }
        1601 { Write-Warning 'Update already in progress. Please try again later.' }
        1704 { Write-Warning 'An Office installation is currently suspended. Please resume the installation and try again.' }
        3010 { Write-Warning 'Office Click-to-Run update requires a reboot to complete.' }
        default { Write-Error -Message "Office Click-to-Run update failed with exit code $exitCode." -Category InvalidResult }
    }

    [pscustomobject]@{
        Channel       = $OfficeChannel
        UpdateChannel = $channelUrl
        ExitCode      = $exitCode
    }
}
