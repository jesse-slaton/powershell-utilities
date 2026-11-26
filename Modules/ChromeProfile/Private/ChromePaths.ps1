# Default locations, read from the environment when a function is called (not at import),
# so the public functions can be tested with these helpers mocked on any OS.

function Get-ChromeDefaultProfilePath {
    <#
    .SYNOPSIS
        Returns the path of the current user's Default Chrome profile folder.

    .DESCRIPTION
        Builds $env:LOCALAPPDATA\Google\Chrome\User Data\Default. Reads nothing from disk and
        does not check that the folder exists. Outputs the path as a string.

    .EXAMPLE
        Get-ChromeDefaultProfilePath

        Returns C:\Users\<user>\AppData\Local\Google\Chrome\User Data\Default.

    .NOTES
        None. Internal to the ChromeProfile module; not exported.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param ()

    [System.IO.Path]::Combine($env:LOCALAPPDATA, 'Google', 'Chrome', 'User Data', 'Default')
}

function Get-ChromeDefaultBackupFolder {
    <#
    .SYNOPSIS
        Returns the default folder for the Chrome profile backup zip.

    .DESCRIPTION
        Builds $env:USERPROFILE\ChromeBackup, the folder Backup-ChromeProfile writes to and
        Restore-ChromeProfile reads from when no folder is given. Reads nothing from disk.
        Outputs the path as a string.

    .EXAMPLE
        Get-ChromeDefaultBackupFolder

        Returns C:\Users\<user>\ChromeBackup.

    .NOTES
        None. Internal to the ChromeProfile module; not exported.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param ()

    Join-Path $env:USERPROFILE 'ChromeBackup'
}
