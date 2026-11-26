function Get-ChromeExtension {
    <#
    .SYNOPSIS
        Outputs the manifest of every Chrome extension in each user's Default Chrome profile.

    .DESCRIPTION
        For each user folder under the user profile root (by default $env:SystemDrive\Users),
        reads every
        <User>\AppData\Local\Google\Chrome\User Data\Default\Extensions\<ExtensionId>\<Version>\manifest.json
        and outputs it as an object from ConvertFrom-Json, with all of the manifest's
        properties (for example name, version and permissions) plus two added ones: User (the
        user folder name) and Path (the full path of manifest.json). Only the Default profile
        is searched. Read-only.

        Folders the current account cannot read, and users without Chrome, are skipped
        silently. A manifest that cannot be read or is not valid JSON writes a non-terminating
        error and the next one is read. A missing user profile root writes a non-terminating
        error and outputs nothing.

        Formerly Scripts/Application/Get-ChromeExtension.ps1 (removed; no deployment tool used
        that path). That script did not output User and Path.

    .PARAMETER UserProfileRoot
        Folder that holds the user profile folders. Defaults to $env:SystemDrive\Users.

    .EXAMPLE
        Get-ChromeExtension | Select-Object User, name, version, Path

        Lists every installed extension version with the user it belongs to.

    .EXAMPLE
        Get-ChromeExtension -UserProfileRoot 'D:\Users' | Where-Object User -eq 'alice'

        Outputs the extension manifests of one user whose profile is on drive D.

    .NOTES
        Run as administrator (or Local System) to read other users' profile folders; without
        it, only folders the current account can read are returned. Part of the ChromeProfile
        module.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [string]$UserProfileRoot
    )

    if (-not $UserProfileRoot) { $UserProfileRoot = Join-Path $env:SystemDrive 'Users' }

    if (-not (Test-Path -LiteralPath $UserProfileRoot -PathType Container)) {
        Write-Error -Message "User profile root not found: $UserProfileRoot" -Category ObjectNotFound -TargetObject $UserProfileRoot
        return
    }

    # Ignore, not SilentlyContinue: an unreadable or Chrome-less profile is expected, not an error.
    foreach ($user in @(Get-ChildItem -LiteralPath $UserProfileRoot -Directory -ErrorAction Ignore)) {
        $extensions = [System.IO.Path]::Combine($user.FullName, 'AppData', 'Local', 'Google', 'Chrome', 'User Data', 'Default', 'Extensions')
        foreach ($extension in @(Get-ChildItem -LiteralPath $extensions -Directory -ErrorAction Ignore)) {
            foreach ($version in @(Get-ChildItem -LiteralPath $extension.FullName -Directory -ErrorAction Ignore)) {
                $manifestPath = Join-Path $version.FullName 'manifest.json'
                if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { continue }
                try {
                    # UTF8 reads a BOM-less manifest as UTF-8 on 5.1 too (its default is the ANSI code page).
                    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                    $manifest | Add-Member -NotePropertyName User -NotePropertyValue $user.Name -Force -PassThru |
                        Add-Member -NotePropertyName Path -NotePropertyValue $manifestPath -Force -PassThru
                }
                catch {
                    Write-Error -Message ("Error reading Chrome extension manifest {0}: {1}" -f $manifestPath, $_.Exception.Message) -TargetObject $manifestPath
                }
            }
        }
    }
}
