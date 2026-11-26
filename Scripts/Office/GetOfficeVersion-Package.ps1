<#
.SYNOPSIS
    Saves the online version list entries for the installed Office Click-to-Run build as CLIXML.

.DESCRIPTION
    Thin wrapper kept at this path for deployment packages. Imports the OfficeC2R module,
    calls Get-OfficeC2RVersion, and exports its output to FilteredVersions.xml in the current
    directory with Export-Clixml, replacing an existing file. Writes no pipeline output.
    See Get-Help Get-OfficeC2RVersion -Full for how the entries are matched.

    The module is imported from the first of these that works:
    1. OfficeC2R/OfficeC2R.psd1 in the folder that holds this script (a package that
       bundles the module folder beside the script).
    2. ../../Modules/OfficeC2R/OfficeC2R.psd1 from this script (a copy of this repository).
    3. The OfficeC2R module by name, from PSModulePath (the module installed on the device).
    When none works it stops with one error that names every location tried.

    Earlier versions also compressed the file to FilteredVersions.zip and expanded it again;
    that round trip did nothing useful and failed on a rerun, so it was dropped.

.EXAMPLE
    .\GetOfficeVersion-Package.ps1

    Writes FilteredVersions.xml to the current directory. Read it back with
    Import-Clixml -Path .\FilteredVersions.xml.

.NOTES
    A deployment package must contain this script and the whole Modules/OfficeC2R folder
    copied as a folder named OfficeC2R beside it (OfficeC2R.psd1, OfficeC2R.psm1, Private
    and Public), unless the OfficeC2R module is already installed on PSModulePath. The
    script alone, or the module files flattened into one folder, is not enough.

    Also requires internet access to functions.office365versions.com (a third-party site),
    write access to the current directory, and Office Click-to-Run installed. Reads HKLM
    without administrator rights.
#>

function Import-OfficeC2RModule {
    <#
    .SYNOPSIS
        Imports the OfficeC2R module from beside the script, the repository, or PSModulePath.

    .DESCRIPTION
        Tries ScriptRoot/OfficeC2R/OfficeC2R.psd1, then
        ScriptRoot/../../Modules/OfficeC2R/OfficeC2R.psd1, then Import-Module OfficeC2R by
        name. Imports the first manifest that exists (an import error from it is
        terminating). When no manifest exists and the import by name fails, throws one
        error naming every location tried. Outputs nothing.

    .PARAMETER ScriptRoot
        The folder that holds the calling script, normally $PSScriptRoot.

    .EXAMPLE
        Import-OfficeC2RModule -ScriptRoot $PSScriptRoot
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptRoot
    )

    $tried = @()
    $manifests = @(
        (Join-Path (Join-Path $ScriptRoot 'OfficeC2R') 'OfficeC2R.psd1'),
        (Join-Path $ScriptRoot '../../Modules/OfficeC2R/OfficeC2R.psd1')
    )
    foreach ($manifest in $manifests) {
        if (Test-Path -LiteralPath $manifest -PathType Leaf) {
            # relative-import-ok: $manifest is built from -ScriptRoot, which the caller passes as $PSScriptRoot
            Import-Module -Name $manifest -Force -Global -ErrorAction Stop
            return
        }
        $tried += $manifest
    }

    try {
        Import-Module -Name 'OfficeC2R' -Force -Global -ErrorAction Stop
        return
    }
    catch {
        $tried += "OfficeC2R by name from PSModulePath ($($_.Exception.Message))"
    }
    throw "The OfficeC2R module was not found. Tried: $($tried -join '; ')."
}

Import-OfficeC2RModule -ScriptRoot $PSScriptRoot
Get-OfficeC2RVersion -ErrorAction Stop | Export-Clixml -Path (Join-Path (Get-Location).ProviderPath 'FilteredVersions.xml')
