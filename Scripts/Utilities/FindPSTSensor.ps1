<#
.SYNOPSIS
    Outputs the PST file inventory from C:\Support\Logs\PSTFiles.json as pipe-delimited lines.

.DESCRIPTION
    Reads the JSON inventory at C:\Support\Logs\PSTFiles.json (written by a separate PST
    discovery package) and outputs one pipe-delimited line per entry, with quotes and the
    header row removed. Outputs "No PST Inventory" when the file does not exist.
    Read-only; intended as a deployment-tool sensor.

.EXAMPLE
    .\FindPSTSensor.ps1

    C:\Users\Public\Archive.pst|2048|2026-01-15

    (Columns depend on the properties stored in PSTFiles.json.)

.NOTES
    Requires the inventory file produced by the PST discovery package. No admin rights
    needed to read it.
#>
$Path = 'C:\Support\Logs\PSTFiles.json'
If (Test-Path -Path $Path) {
    $JSON = Get-Content -Path $Path | ConvertFrom-Json
    ($JSON | ConvertTo-Csv -Delimiter '|' -NoTypeInformation).Replace('"','') | Select-Object -Skip 1
}
Else {
    Write-Output 'No PST Inventory'
}