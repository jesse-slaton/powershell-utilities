function Restore-ChromeProfile {
    <#
    .SYNOPSIS
        Restores a missing Google Chrome profile folder from ChromeProfileBackup.zip.

    .DESCRIPTION
        Extracts ChromeProfileBackup.zip (written by Backup-ChromeProfile) from the backup
        folder into the profile folder (by default the current user's Default profile,
        $env:LOCALAPPDATA\Google\Chrome\User Data\Default), then deletes the zip. Restores
        only when the profile folder does not exist: an existing profile is never overwritten.
        Outputs the restored profile folder (a DirectoryInfo object).

        When the profile folder already exists, or the backup zip is missing, it writes a
        warning, changes nothing and outputs nothing. A zip in the old backup script's layout
        (see below) writes a non-terminating error, keeps the zip and creates nothing. The zip is
        extracted into a temporary sibling folder that is renamed into place, so a profile that
        appears during the restore (Chrome creates one when it starts) is never written to or
        deleted. A failed extraction removes only that temporary folder, keeps the zip and
        writes a non-terminating error.

        Formerly Scripts/FileSystem/ChromeProfileRestore.ps1 (removed; no deployment tool used
        that path). A zip made by the old ChromeProfileBackup.ps1 holds everything under a
        ChromeProfileBackup folder; it is refused with an error and kept. To migrate one,
        extract it and copy the contents of its ChromeProfileBackup folder (or of
        ChromeProfileBackup\Default, when present) into the profile folder by hand.

    .PARAMETER Path
        Folder that holds ChromeProfileBackup.zip. Defaults to $env:USERPROFILE\ChromeBackup.

    .PARAMETER ProfilePath
        The Chrome profile folder to restore. Defaults to the current user's Default profile.

    .EXAMPLE
        Restore-ChromeProfile

        Restores the Default profile from $env:USERPROFILE\ChromeBackup\ChromeProfileBackup.zip
        if the profile is missing.

    .EXAMPLE
        Restore-ChromeProfile -Path 'D:\Backups' -ProfilePath "$env:LOCALAPPDATA\Google\Chrome\User Data\Profile 1"

        Restores the "Profile 1" profile from D:\Backups\ChromeProfileBackup.zip.

    .NOTES
        Run as the user whose profile is restored, with Chrome closed. No admin rights
        needed. Part of the ChromeProfile module.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.DirectoryInfo])]
    param (
        [string]$Path,

        [string]$ProfilePath
    )

    if (-not $Path) { $Path = Get-ChromeDefaultBackupFolder }
    if (-not $ProfilePath) { $ProfilePath = Get-ChromeDefaultProfilePath }
    # Resolve to a literal file-system path: '[' and ']' in a profile name (for example
    # 'Profile [1]') must never be read as a wildcard pattern that matches another profile.
    $ProfilePath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($ProfilePath)

    if (Test-Path -LiteralPath $ProfilePath) {
        Write-Warning "Chrome profile folder already exists, not restored: $ProfilePath"
        return
    }

    $zipFile = Join-Path $Path 'ChromeProfileBackup.zip'
    if (-not (Test-Path -LiteralPath $zipFile -PathType Leaf)) {
        Write-Warning "No backup file found, Chrome profile not restored: $zipFile"
        return
    }

    # Extract into a sibling folder this call creates, then rename it into place. The rename fails
    # if the profile appeared meanwhile (Chrome creates one when it starts), so a profile this call
    # did not create is never written to or deleted.
    $stagingPath = '{0}.partial-{1}' -f $ProfilePath, [guid]::NewGuid().ToString('N').Substring(0, 8)
    try {
        # The old ChromeProfileBackup.ps1 zipped a staging folder, so every entry sits under a
        # ChromeProfileBackup root (5.1 Compress-Archive writes '\' separators, 7 writes '/').
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $zipFile).ProviderPath)
        try {
            $entries = @($archive.Entries)
            $legacy = $entries.Count -gt 0
            foreach ($entry in $entries) {
                if (-not ($entry.FullName.StartsWith('ChromeProfileBackup/', [System.StringComparison]::Ordinal) -or $entry.FullName.StartsWith('ChromeProfileBackup\', [System.StringComparison]::Ordinal))) {
                    $legacy = $false
                    break
                }
            }
        }
        finally {
            $archive.Dispose()
        }
        if (-not $legacy) {
            Write-Verbose "Restoring Chrome profile $ProfilePath from $zipFile"
            # Expand-Archive has no literal -DestinationPath and resolves it as a wildcard pattern,
            # so 'Profile [1]' could extract into an existing 'Profile 1'. ZipFile takes it as is.
            [System.IO.Compression.ZipFile]::ExtractToDirectory((Resolve-Path -LiteralPath $zipFile).ProviderPath, $stagingPath)
            [System.IO.Directory]::Move($stagingPath, $ProfilePath)
        }
    }
    catch {
        # Only the staging folder is this call's own; drop it so a re-run can retry.
        if (Test-Path -LiteralPath $stagingPath) { Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction SilentlyContinue }
        Write-Error -Message ("Error restoring Chrome profile {0} from {1}: {2}" -f $ProfilePath, $zipFile, $_.Exception.Message) -TargetObject $zipFile
        return
    }
    if ($legacy) {
        Write-Error -Message ("{0} was made by the old ChromeProfileBackup.ps1 script (its files are under a ChromeProfileBackup folder), so it was not restored. Extract it and copy the contents of its ChromeProfileBackup folder (or of ChromeProfileBackup\Default, when present) into {1}." -f $zipFile, $ProfilePath) -Category InvalidData -TargetObject $zipFile
        return
    }
    Remove-Item -LiteralPath $zipFile -Force
    Get-Item -LiteralPath $ProfilePath
}
