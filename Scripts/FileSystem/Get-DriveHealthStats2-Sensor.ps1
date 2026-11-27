<#
.SYNOPSIS
    Reports selected SMART attribute values from smartctl as pipe-delimited lines.

.DESCRIPTION
    Thin wrapper kept at this path because a deployment tool runs it by name (the -Sensor
    suffix). Imports the StorageHealth module, calls Get-DriveHealth -Source Smartctl and
    writes one line per fixed drive that smartctl reports attributes for:

        <DriveLetter>|<FriendlyName>|<SerialNumber>|<5>|<187>|<188>|<197>|<198>

    where the numbered fields are the normalized VALUE column of SMART attributes 5, 187,
    188, 197 and 198 (empty when the attribute is not reported). Reads only; changes
    nothing. The logic and its help live in the module (Get-Help Get-DriveHealth -Full).

    Output change from the former script: it wrote one line for the last drive only; this
    writes one line per drive, and no line when no drive reports SMART attributes.

    When the module cannot be loaded, writes the single line
    'StorageHealth module not found|Sensor error|<message>|||||' and exits 1, so a broken
    deployment is never read as "no drive reported". When a drive cannot be read (smartctl
    cannot open a VHD, a Storage Spaces or RAID volume, or some USB enclosures), the other
    drives are still reported, followed by one
    'Drive health could not be read|Sensor error|<message>|||||' line per failure, and the
    sensor exits 1. A failure that stops the whole read (for example, no Storage module)
    writes that line once and exits 1. Every error line has the same eight columns as a
    drive line.

.EXAMPLE
    .\Get-DriveHealthStats2-Sensor.ps1

    C:|<FriendlyName>|<SerialNumber>|<Value5>|<Value187>|<Value188>|<Value197>|<Value198>

.NOTES
    Needs the StorageHealth module either at ..\..\Modules\StorageHealth relative to this
    script, as it is in a clone of this repository, or installed in a folder on
    $env:PSModulePath. A sensor body pasted into a deployment tool runs from a temporary
    folder with no Modules folder beside it, so on those endpoints StorageHealth must be
    installed on $env:PSModulePath. Also needs smartctl.exe (smartmontools) on the PATH,
    administrator rights, and the Storage module (Get-Partition, Get-Disk). Runs on Windows
    PowerShell 5.1 and PowerShell 7.
#>
[CmdletBinding()]
param ()

# No output means no drive reported SMART attributes, so a failed import must still print a line.
try {
    if ($PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot '../../Modules/StorageHealth/StorageHealth.psd1'))) {
        Import-Module (Join-Path $PSScriptRoot '../../Modules/StorageHealth/StorageHealth.psd1') -Force -ErrorAction Stop
    }
    else {
        Import-Module StorageHealth -Force -ErrorAction Stop
    }
} catch {
    'StorageHealth module not found|Sensor error|{0}|||||' -f ($_.Exception.Message -replace '[\r\n|]+', ' ')
    exit 1
}

# One unreadable drive writes a non-terminating error; it must not hide the readable drives.
$driveErrors = @()
try {
    $drives = @(Get-DriveHealth -Source Smartctl -ErrorAction SilentlyContinue -ErrorVariable driveErrors)
} catch {
    'Drive health could not be read|Sensor error|{0}|||||' -f ($_.Exception.Message -replace '[\r\n|]+', ' ')
    exit 1
}
foreach ($health in $drives) {
    @(
        $health.DriveLetter, $health.FriendlyName, $health.SerialNumber,
        $health.ReallocatedSectorsCount, $health.ReportedUncorrectableErrors, $health.CommandTimeout,
        $health.CurrentPendingSectorCount, $health.UncorrectableSectorCount
    ) -join '|'
}
foreach ($driveError in $driveErrors) {
    'Drive health could not be read|Sensor error|{0}|||||' -f ($driveError.Exception.Message -replace '[\r\n|]+', ' ')
}
if ($driveErrors.Count -gt 0) {
    exit 1
}
