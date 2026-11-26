function Backup-ChromeProfile {
    <#
    .SYNOPSIS
        Backs up a Google Chrome profile folder to ChromeProfileBackup.zip.

    .DESCRIPTION
        Compresses the contents of a Chrome profile folder (by default the current user's
        Default profile, $env:LOCALAPPDATA\Google\Chrome\User Data\Default) into
        ChromeProfileBackup.zip in the destination folder, which is created if missing. An
        existing ChromeProfileBackup.zip there is replaced only when the new backup succeeds;
        a failed backup leaves it as it was. The zip holds the profile's
        contents at its root, so Restore-ChromeProfile can extract it straight into a profile
        folder. Outputs the zip file (a FileInfo object).

        A missing profile folder, or a failure to create the folder or the zip, writes a
        non-terminating error and outputs nothing. So does a folder whose only top-level item is
        a folder named ChromeProfileBackup: Restore-ChromeProfile would read that zip as the
        old backup script's layout and refuse it (a real Chrome profile always has files at its
        root).

        Formerly Scripts/FileSystem/ChromeProfileBackup.ps1 (removed; no deployment tool used
        that path). That script copied the profile to a staging folder first and zipped the
        folder itself, so its zip could not be restored into the profile; the staging copy is
        gone.

    .PARAMETER Destination
        Folder that receives ChromeProfileBackup.zip. Created if it does not exist. Defaults
        to $env:USERPROFILE\ChromeBackup.

    .PARAMETER ProfilePath
        The Chrome profile folder to back up. Defaults to the current user's Default profile.

    .EXAMPLE
        Backup-ChromeProfile

        Writes $env:USERPROFILE\ChromeBackup\ChromeProfileBackup.zip from the Default profile.

    .EXAMPLE
        Backup-ChromeProfile -Destination 'D:\Backups' -ProfilePath "$env:LOCALAPPDATA\Google\Chrome\User Data\Profile 1"

        Backs up the "Profile 1" profile to D:\Backups\ChromeProfileBackup.zip.

    .NOTES
        Run as the user whose profile is backed up, with Chrome closed (Chrome locks some
        profile files while it runs, and those make the backup fail). No admin rights needed.
        A backup that is killed mid-write can leave a ChromeProfileBackup.partial-<id>.zip in the
        destination; it is never restored and is safe to delete once no backup is running.
        Compress-Archive skips hidden files and folders at any depth and empty folders
        directly in the profile folder, and cannot add a file larger than 2 GB (#161). Part of
        the ChromeProfile module.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param (
        [string]$Destination,

        [string]$ProfilePath
    )

    if (-not $Destination) { $Destination = Get-ChromeDefaultBackupFolder }
    if (-not $ProfilePath) { $ProfilePath = Get-ChromeDefaultProfilePath }

    if (-not (Test-Path -LiteralPath $ProfilePath -PathType Container)) {
        Write-Error -Message "Chrome profile folder not found: $ProfilePath" -Category ObjectNotFound -TargetObject $ProfilePath
        return
    }

    # Resolve to a literal file-system path: '[' and ']' in a folder name must never be read as a
    # wildcard pattern that matches a different folder.
    $Destination = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Destination)
    $zipFile = Join-Path $Destination 'ChromeProfileBackup.zip'
    # Write a temp zip with a name of this run's own (Compress-Archive on 5.1 needs the .zip
    # extension) and swap it in only on success, so a failed backup never destroys the previous
    # good one and two backups to the same folder never publish each other's zip. A new name also
    # keeps Compress-Archive away from its replace-existing branch, which reads the path as a
    # wildcard pattern.
    $tempZip = Join-Path $Destination ('ChromeProfileBackup.partial-{0}.zip' -f [guid]::NewGuid().ToString('N'))
    try {
        # New-Item has no -LiteralPath; the .NET call takes the path as it is.
        $null = [System.IO.Directory]::CreateDirectory($Destination)
        # Wildcard the contents so the zip root is the profile itself, not a folder named after it.
        $source = Join-Path ([System.Management.Automation.WildcardPattern]::Escape($ProfilePath)) '*'
        # -DestinationPath has no literal form; Compress-Archive unescapes it to a provider path first.
        $null = Compress-Archive -Path $source -DestinationPath ([System.Management.Automation.WildcardPattern]::Escape($tempZip)) -ErrorAction Stop
        # Restore-ChromeProfile refuses a zip whose every entry is under a ChromeProfileBackup folder
        # (the old script's layout). Check the zip as written, so it never replaces a good backup
        # with one that cannot be restored. A real Chrome profile always has files at its root.
        if (Test-ChromeLegacyBackupZip -Path $tempZip) {
            throw "every item in the backup is under a folder named ChromeProfileBackup, so Restore-ChromeProfile would read it as the old backup layout and it could not be restored. Back up the folder that holds the profile files instead."
        }
        Move-Item -LiteralPath $tempZip -Destination $zipFile -Force -ErrorAction Stop
        Get-Item -LiteralPath $zipFile
    }
    catch {
        if (Test-Path -LiteralPath $tempZip) { Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue }
        Write-Error -Message ("Error backing up Chrome profile {0} to {1}: {2}" -f $ProfilePath, $zipFile, $_.Exception.Message) -TargetObject $ProfilePath
    }
}
