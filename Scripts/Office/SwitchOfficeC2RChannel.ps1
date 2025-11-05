<#
.SYNOPSIS
Switches an Office Click-to-Run install from its existing channel to a new channel.

.DESCRIPTION
This PowerShell script switches the Office Click-to-Run installation to a new update channel
by updating the CDNBaseUrl registry value and running the OfficeC2RClient.exe with the
appropriate arguments to apply the changes. The script tests connectivity to the Office CDN,
updates registry settings, and forces an Office update from the new channel.

.PARAMETER OfficeChannel
Specifies the new update channel for Office. Valid values are:
- Current: Latest features as soon as they're available
- MonthlyEnterprise: Monthly feature updates on a predictable schedule
- SemiAnnual: Feature updates twice per year
- Beta: Early preview builds for testing
Default value is "SemiAnnual".

.EXAMPLE
.\SwitchOfficeC2RChannel.ps1
Switches Office to the SemiAnnual channel (default) and applies the update.

.EXAMPLE
.\SwitchOfficeC2RChannel.ps1 -OfficeChannel Current
Switches Office to the Current channel for immediate feature updates.

.EXAMPLE
.\SwitchOfficeC2RChannel.ps1 -OfficeChannel MonthlyEnterprise -Verbose
Switches Office to the Monthly Enterprise channel with verbose output showing progress.

.NOTES
Author: Jesse Slaton
Date: 2023-03-31
Requires: Administrator privileges
Exit Codes: 0=Success, 1601=Update in progress, 1704=Installation suspended, 3010=Reboot required

.LINK
https://docs.microsoft.com/en-us/deployoffice/overview-update-channels
#>

param(
    [ValidateSet("Current", "MonthlyEnterprise", "SemiAnnual", "Beta")]
    [string]$OfficeChannel = "SemiAnnual"
)

function Test-OfficeCdnConnectivity {
    param (
        $Uri = 'https://officecdn.microsoft.com/pr/wsus/ofl.cab'
    )
    Write-Verbose "Attempting to read file size from $Uri"
    try {
        [int]$Size = (Invoke-WebRequest -Uri $Uri -Method Head -ErrorAction Stop -UseBasicParsing).Headers.'Content-Length' | Select-String -Pattern '\d+' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $_.Value }
        Write-Verbose "ofl.cab has size $Size"
        if ($Size -gt 0) {
            Write-Verbose "Size is greater than 0"
            return $true
        }
        else {
            Write-Warning "Size is not greater than 0"
            return $false
        }
    }
    catch {
        Write-Warning "Unable to read file size from $Uri"
        return $false
    }
}

$registryPath = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration\"
$key = "UpdateChannel"
$channelUrl = switch ($OfficeChannel) {
    "Current" { "http://officecdn.microsoft.com/pr/492350f6-3a01-4f97-b9c0-c7c6ddf67d60" }
    "MonthlyEnterprise" { "http://officecdn.microsoft.com/pr/64256afe-f5d9-4f86-8936-8840a6a4f5be" }
    "SemiAnnual" { "http://officecdn.microsoft.com/pr/b8f9b850-328d-4355-9145-c59439a0c4cf" }
    "Beta" { "http://officecdn.microsoft.com/pr/7ffbc6bf-bc32-4f92-8982-f9dd17fd3114" }
}

New-Item -Path $registryPath -Force | Out-Null
Set-ItemProperty -Path $registryPath -Name $key -Value $channelUrl -Type String

New-Item -Path "HKCU:\SOFTWARE\Policies\Microsoft\office\16.0\Common" -Force | Out-Null
New-Item -Path "HKCU:\SOFTWARE\Policies\Microsoft\office\16.0\Common\officeupdate" -Force | Out-Null
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -Name 'updatebranch' -Value $OfficeChannel -Type String

Set-Location $PSScriptRoot;
$proc = (Start-Process -FilePath "C:\Program Files\Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe" -ArgumentList "/update user displaylevel=false forceappshutdown=true" -Wait -PassThru)
$proc.WaitForExit()
$ExitCode = $proc.ExitCode

# Human-friendly output based on $ExitCode
switch ($ExitCode) {
    0 { Write-Output "Success: Office Click-to-Run update completed successfully." }
    1601 { Write-Warning "Warning: Update already in progress. Please try again later." }
    1704 { Write-Warning "Warning: An Office installation is currently suspended. Please resume the installation and try again." }
    3010 { Write-Warning "Warning: Office Click-to-Run update requires a reboot to complete." }
    default { Write-Error "Error: Office Click-to-Run update failed with exit code $($ExitCode)." }
}

Exit $ExitCode