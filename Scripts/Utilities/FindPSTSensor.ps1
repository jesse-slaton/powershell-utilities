$Path = 'C:\Support\Logs\PSTFiles.json'
If (Test-Path -Path $Path) {
    $JSON = Get-Content -Path $Path | ConvertFrom-Json
    ($JSON | ConvertTo-Csv -Delimiter '|' -NoTypeInformation).Replace('"','') | Select-Object -Skip 1
}
Else {
    Write-Output 'No PST Inventory'
}