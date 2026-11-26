function Backup-ChromeBookmark {
    <#
    .SYNOPSIS
        Copies a Chrome profile's Bookmarks file to a backup folder.

    .DESCRIPTION
        Copies the Bookmarks file of a Chrome profile (by default the current user's Default
        profile, $env:LOCALAPPDATA\Google\Chrome\User Data\Default) to
        <Destination>\Chrome-Bookmarks. The destination folder is created if missing and an
        existing Chrome-Bookmarks there is replaced. Outputs the copy (a FileInfo object).

        A missing Bookmarks file, or a failed copy, writes a non-terminating error and outputs
        nothing.

        Formerly Scripts/Backup/Backup-ChromeBookmarks.ps1 (removed; no deployment tool used
        that path); that name is kept as an alias. The script's -BackupPath, which defaulted to
        an organization-specific folder, is now the mandatory -Destination (BackupPath is kept as
        a parameter alias).

    .PARAMETER Destination
        Folder that receives the Chrome-Bookmarks copy. Created if it does not exist.

    .PARAMETER ProfilePath
        The Chrome profile folder that holds the Bookmarks file. Defaults to the current
        user's Default profile.

    .EXAMPLE
        Backup-ChromeBookmark -Destination 'D:\Backups'

        Copies the Default profile's bookmarks to D:\Backups\Chrome-Bookmarks.

    .EXAMPLE
        Backup-ChromeBookmark -Destination '\\server\share\bookmarks' -ProfilePath "$env:LOCALAPPDATA\Google\Chrome\User Data\Profile 1"

        Copies the "Profile 1" bookmarks to a network share.

    .NOTES
        Run as the user whose bookmarks are backed up. No admin rights needed unless the
        destination requires them. Restore-ChromeBookmark copies the file back. Part of the
        ChromeProfile module.
    #>
    [CmdletBinding()]
    [Alias('Backup-ChromeBookmarks')]
    [OutputType([System.IO.FileInfo])]
    param (
        [Parameter(Mandatory = $true)]
        [Alias('BackupPath')]
        [string]$Destination,

        [string]$ProfilePath
    )

    if (-not $ProfilePath) { $ProfilePath = Get-ChromeDefaultProfilePath }

    $bookmarks = Join-Path $ProfilePath 'Bookmarks'
    if (-not (Test-Path -LiteralPath $bookmarks -PathType Leaf)) {
        Write-Error -Message "Chrome bookmarks file not found: $bookmarks" -Category ObjectNotFound -TargetObject $bookmarks
        return
    }

    $copy = Join-Path $Destination 'Chrome-Bookmarks'
    try {
        $null = New-Item -ItemType Directory -Path $Destination -Force -ErrorAction Stop
        Copy-Item -LiteralPath $bookmarks -Destination $copy -Force -PassThru -ErrorAction Stop
    }
    catch {
        Write-Error -Message ("Error copying Chrome bookmarks {0} to {1}: {2}" -f $bookmarks, $copy, $_.Exception.Message) -TargetObject $bookmarks
    }
}
