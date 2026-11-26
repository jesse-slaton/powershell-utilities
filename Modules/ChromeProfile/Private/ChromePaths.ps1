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

function Resolve-ChromeFileSystemPath {
    <#
    .SYNOPSIS
        Resolves a path to an absolute file-system path, refusing any other PowerShell provider.

    .DESCRIPTION
        Uses the calling cmdlet's GetUnresolvedProviderPathFromPSPath, which takes the path
        literally (no wildcards) and resolves a relative path against the PowerShell location.
        Throws when the path belongs to a provider other than FileSystem (for example Variable:\
        or HKCU:\), whose provider-internal path .NET would otherwise resolve against the
        process working directory.

    .PARAMETER Path
        The path to resolve.

    .PARAMETER Cmdlet
        The calling cmdlet's $PSCmdlet.

    .EXAMPLE
        Resolve-ChromeFileSystemPath -Path '.\Backup' -Cmdlet $PSCmdlet

        Returns the absolute path of .\Backup.

    .NOTES
        Internal to the ChromeProfile module; not exported.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet]$Cmdlet
    )

    $provider = $null
    $drive = $null
    $resolved = $Cmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path, [ref]$provider, [ref]$drive)
    if ($provider.Name -ne 'FileSystem') {
        throw "'$Path' is not a file-system path (provider $($provider.Name))"
    }
    $resolved
}
