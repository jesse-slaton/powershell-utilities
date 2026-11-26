<#
.SYNOPSIS
    Sensor: reports malformed PATH entries as pipe-delimited lines.

.DESCRIPTION
    Thin wrapper around Get-MalformedPathEntry in the PathRepair module. Imports the module
    from Modules/PathRepair beside this repository's Scripts folder and writes one line per
    malformed entry of the current process PATH:

        <Entry>|<Issue>|<SuggestedEntry>

    Writes nothing when PATH has no malformed entries. When the module cannot be loaded, writes
    the single line 'PathRepair module not found|Sensor error|<message>' and exits 1, so a
    broken deployment is never read as a healthy PATH. Likewise, when PATH cannot be analyzed
    (for example it is empty), writes 'PATH could not be analyzed|Sensor error|<message>' and
    exits 1. Reads only; changes nothing. Kept at
    this path because a deployment tool runs it by name (the -Sensor suffix); the logic and
    its help live in the module (Get-Help Get-MalformedPathEntry -Full).

.EXAMPLE
    .\Get-MalformedPathEntries-Sensor.ps1

    Writes the malformed entries of the current PATH, one pipe-delimited line each.

.NOTES
    Needs the Modules/PathRepair folder deployed at ..\..\Modules\PathRepair relative to
    this script, as it is in a clone of this repository.
#>
[CmdletBinding()]
param ()

# Empty stdout means a healthy PATH, so a failed import must still print a line.
try {
    if ([string]::IsNullOrEmpty($PSScriptRoot)) {
        throw 'The script folder is unknown; run this sensor as a file, not as a script body.'
    }
    Import-Module (Join-Path $PSScriptRoot '../../Modules/PathRepair/PathRepair.psd1') -Force -ErrorAction Stop
} catch {
    'PathRepair module not found|Sensor error|{0}' -f ($_.Exception.Message -replace '[\r\n|]+', ' ')
    exit 1
}

# An empty PATH is reported as an error with no entries, which would also read as healthy.
try {
    $entries = @(Get-MalformedPathEntry -ErrorAction Stop)
} catch {
    'PATH could not be analyzed|Sensor error|{0}' -f ($_.Exception.Message -replace '[\r\n|]+', ' ')
    exit 1
}
$entries | ForEach-Object {
    "$($_.Entry)|$($_.Issue)|$($_.SuggestedEntry)"
}
