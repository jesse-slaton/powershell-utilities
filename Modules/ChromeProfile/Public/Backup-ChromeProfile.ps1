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
        root). A profile folder with no files in it (at any depth) is refused the same way, so an
        emptied profile never replaces the last good backup. A -Destination or -ProfilePath on a
        provider other than the file system (Variable:\, HKCU:\) is an error and writes nothing.
        A folder named ChromeProfileBackup.zip in the destination is an error too.

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
        Hidden files and folders and empty folders at any depth are included (hidden ones are
        restored as ordinary, non-hidden items), and folder names with '[' or ']' are used
        literally. Part of the ChromeProfile module.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param (
        [string]$Destination,

        [string]$ProfilePath
    )

    if (-not $Destination) { $Destination = Get-ChromeDefaultBackupFolder }
    if (-not $ProfilePath) { $ProfilePath = Get-ChromeDefaultProfilePath }

    # Resolve to literal file-system paths: '[' and ']' in a folder name must never be read as a
    # wildcard pattern that matches a different folder, and .NET must get absolute paths. A path
    # on another provider (Variable:\) is refused: .NET would resolve it against the process directory.
    try {
        $Destination = Resolve-ChromeFileSystemPath -Path $Destination -Cmdlet $PSCmdlet
        $ProfilePath = Resolve-ChromeFileSystemPath -Path $ProfilePath -Cmdlet $PSCmdlet
    }
    catch {
        Write-Error -Message "Error backing up Chrome profile: $($_.Exception.Message)" -Category InvalidArgument
        return
    }

    if (-not (Test-Path -LiteralPath $ProfilePath -PathType Container)) {
        Write-Error -Message "Chrome profile folder not found: $ProfilePath" -Category ObjectNotFound -TargetObject $ProfilePath
        return
    }

    $zipFile = Join-Path $Destination 'ChromeProfileBackup.zip'
    # Write a temp zip with a name of this run's own and swap it in only on success, so a failed
    # backup never destroys the previous good one and two backups to the same folder never
    # publish each other's zip.
    $tempZip = Join-Path $Destination ('ChromeProfileBackup.partial-{0}.zip' -f [guid]::NewGuid().ToString('N'))
    try {
        if (Test-Path -LiteralPath $zipFile -PathType Container) {
            throw "a folder named ChromeProfileBackup.zip is in the way; remove or rename it"
        }
        # New-Item has no -LiteralPath; the .NET call takes the path as it is.
        $null = [System.IO.Directory]::CreateDirectory($Destination)
        # Zip root is the profile's contents (not a folder named after it); hidden and empty
        # entries are included.
        New-ChromeBackupZip -SourcePath $ProfilePath -ZipPath $tempZip
        # Restore-ChromeProfile refuses a zip whose every entry is under a ChromeProfileBackup folder
        # (the old script's layout). Check the zip as written, so it never replaces a good backup
        # with one that cannot be restored. A real Chrome profile always has files at its root.
        if (Test-ChromeLegacyBackupZip -Path $tempZip) {
            throw "every item in the backup is under a folder named ChromeProfileBackup, so Restore-ChromeProfile would read it as the old backup layout and it could not be restored. Back up the folder that holds the profile files instead."
        }
        # An emptied profile makes a zip with no files; it must not replace a good backup.
        if (-not (Test-ChromeZipHasFile -Path $tempZip)) {
            throw "the profile folder holds no files, so the backup would be empty; the previous backup was kept"
        }
        Move-Item -LiteralPath $tempZip -Destination $zipFile -Force -ErrorAction Stop
        Get-Item -LiteralPath $zipFile
    }
    catch {
        if (Test-Path -LiteralPath $tempZip) { Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue }
        Write-Error -Message ("Error backing up Chrome profile {0} to {1}: {2}" -f $ProfilePath, $zipFile, $_.Exception.Message) -TargetObject $ProfilePath
    }
}
