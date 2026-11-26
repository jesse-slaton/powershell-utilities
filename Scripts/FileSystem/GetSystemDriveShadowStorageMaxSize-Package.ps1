<#
.SYNOPSIS
    Outputs the shadow storage maximum size of the system drive as a percentage and in GB.

.DESCRIPTION
    Thin wrapper kept at this path for the deployment package that runs it. Imports the
    StorageHealth module (from this repository's Modules folder when present, otherwise from
    $env:PSModulePath), calls Get-ShadowStorageMaxSize and writes one line:

        <MaxSpacePercent>|<MaxSpaceGB>

    Both values are rounded to two decimals. If the size cannot be determined, writes the
    error "Could not determine the Shadow Storage MaxSpace". Read-only.

    The former 32-bit to 64-bit powershell.exe (sysnative) relaunch is gone. It was needed
    because Win32_ShadowStorage cannot be read from 32-bit PowerShell on 64-bit Windows;
    Get-ShadowStorageMaxSize now asks WMI for the 64-bit provider itself, so this runs from
    either bitness without forcing Windows PowerShell 5.1.

.EXAMPLE
    .\GetSystemDriveShadowStorageMaxSize-Package.ps1

    <MaxSpacePercent>|<MaxSpaceGB>

.NOTES
    Written as a deployment package. Needs the StorageHealth module either at
    ..\..\Modules\StorageHealth relative to this script, as it is in a clone of this
    repository, or installed in a folder on $env:PSModulePath; a package that ships only this
    file needs the module installed on every endpoint. Also needs, normally, administrator
    rights. Runs on Windows PowerShell 5.1 and PowerShell 7.
#>
$manifest = Join-Path $PSScriptRoot '..\..\Modules\StorageHealth\StorageHealth.psd1'
if (Test-Path -LiteralPath $manifest) {
    Import-Module $manifest -ErrorAction Stop
}
else {
    Import-Module StorageHealth -ErrorAction Stop
}

Try {
    $size = Get-ShadowStorageMaxSize -ErrorAction Stop
    Write-Output "$($size.MaxSpacePercent)|$($size.MaxSpaceGB)"
}
Catch {
    Write-Error "Could not determine the Shadow Storage MaxSpace"
}
