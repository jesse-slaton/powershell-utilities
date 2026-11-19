<#
.SYNOPSIS
    Outputs the manifest of every Chrome extension in each user's Default Chrome profile.

.DESCRIPTION
    Finds every manifest.json under
    C:\Users\*\AppData\Local\Google\Chrome\User Data\Default\Extensions\<ExtensionId>\<Version>\
    (errors suppressed with -ErrorAction SilentlyContinue), reads each one with
    Get-Content -Raw, and outputs it as an object from ConvertFrom-Json, with all of the
    manifest's properties (for example name, version and permissions). The objects do
    not say which user or folder they came from: the Select-Object that would add User
    and Path is commented out. Only the Default profile is searched. Read-only.

.EXAMPLE
    .\Get-ChromeExtension.ps1

    Outputs one manifest object per installed extension version.

.EXAMPLE
    .\Get-ChromeExtension.ps1 | Select-Object name, version

    Lists the name and version fields of each manifest.

.NOTES
    Run as administrator (or Local System) to read other users' profile folders;
    without it, only folders the current account can read are returned.
#>
Get-ChildItem "c:\users\*\appdata\local\Google\Chrome\User Data\Default\Extensions\*\*\manifest.json" -ErrorAction SilentlyContinue | ForEach-Object {
    $path = $_.FullName
    $_.FullName -match 'users\\(.*?)\\appdata' | Out-Null
    Get-Content $_.FullName -Raw | ConvertFrom-Json #| Select-Object  @{n = 'User'; e = { $Matches[1] } }, Name, Version, @{n = 'Path'; e = { $path } }
}
