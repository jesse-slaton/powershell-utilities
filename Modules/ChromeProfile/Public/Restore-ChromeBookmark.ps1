function Restore-ChromeBookmark {
    <#
    .SYNOPSIS
        Restores a Chrome profile's Bookmarks file from a backup folder.

    .DESCRIPTION
        Copies <Path>\Chrome-Bookmarks (written by Backup-ChromeBookmark) over the Bookmarks
        file of a Chrome profile (by default the current user's Default profile,
        $env:LOCALAPPDATA\Google\Chrome\User Data\Default), replacing it. Outputs the restored
        Bookmarks file (a FileInfo object).

        A missing backup copy, a missing profile folder, or a failed copy writes a
        non-terminating error, changes nothing and outputs nothing.

        Formerly Scripts/Backup/Restore-ChromeBookmarks.ps1 (removed; no deployment tool used
        that path); that name is kept as an alias. The script's -BackupPath, which defaulted to
        an organization-specific folder, is now the mandatory -Path (BackupPath is kept as a
        parameter alias).

    .PARAMETER Path
        Folder that holds the Chrome-Bookmarks copy.

    .PARAMETER ProfilePath
        The Chrome profile folder whose Bookmarks file is replaced. Defaults to the current
        user's Default profile. The folder must exist.

    .EXAMPLE
        Restore-ChromeBookmark -Path 'D:\Backups'

        Restores the Default profile's bookmarks from D:\Backups\Chrome-Bookmarks.

    .EXAMPLE
        Restore-ChromeBookmark -Path 'D:\Backups' -ProfilePath "$env:LOCALAPPDATA\Google\Chrome\User Data\Profile 1"

        Restores the "Profile 1" bookmarks.

    .NOTES
        Run as the user whose bookmarks are restored, with Chrome closed (Chrome rewrites the
        file on exit). No admin rights needed. Part of the ChromeProfile module.
    #>
    [CmdletBinding()]
    [Alias('Restore-ChromeBookmarks')]
    [OutputType([System.IO.FileInfo])]
    param (
        [Parameter(Mandatory = $true)]
        [Alias('BackupPath')]
        [string]$Path,

        [string]$ProfilePath
    )

    if (-not $ProfilePath) { $ProfilePath = Get-ChromeDefaultProfilePath }

    $copy = Join-Path $Path 'Chrome-Bookmarks'
    if (-not (Test-Path -LiteralPath $copy -PathType Leaf)) {
        Write-Error -Message "Chrome bookmarks backup not found: $copy" -Category ObjectNotFound -TargetObject $copy
        return
    }
    if (-not (Test-Path -LiteralPath $ProfilePath -PathType Container)) {
        Write-Error -Message "Chrome profile folder not found: $ProfilePath" -Category ObjectNotFound -TargetObject $ProfilePath
        return
    }

    $bookmarks = Join-Path $ProfilePath 'Bookmarks'
    try {
        Copy-Item -LiteralPath $copy -Destination $bookmarks -Force -PassThru -ErrorAction Stop
    }
    catch {
        Write-Error -Message ("Error restoring Chrome bookmarks {0} from {1}: {2}" -f $bookmarks, $copy, $_.Exception.Message) -TargetObject $copy
    }
}
