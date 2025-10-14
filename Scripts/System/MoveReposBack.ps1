$exclude = @('my-calibre-plugins', 'reading-goal', 'calibre', 'lexos-cli', 'lexos-cli-build', 'Readarr')
$source = 'D:\dev\repos'
$dest = 'D:\Dev\PowerShell-Projects'

Get-ChildItem -Path $source -Directory | Where-Object { $_.Name -notin $exclude } | ForEach-Object {
    Write-Host "Moving: $($_.Name)" -ForegroundColor Cyan
    Move-Item -Path $_.FullName -Destination $dest -Force
}

Write-Host "`nMove complete!" -ForegroundColor Green
Write-Host "`nRemaining in D:\dev\repos:" -ForegroundColor Yellow
Get-ChildItem -Path $source -Directory | Select-Object -ExpandProperty Name
