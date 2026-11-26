# PathRepair loader. Standard layout (see README.md, "Modules"): dot-source Private/*.ps1
# then Public/*.ps1, and export the Public functions. The manifest's FunctionsToExport
# and AliasesToExport are the authoritative export lists.

$private = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -File -ErrorAction SilentlyContinue)
$public = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -File -ErrorAction SilentlyContinue)

foreach ($file in @($private + $public)) {
    . $file.FullName
}

if ($public.Count -gt 0) {
    Export-ModuleMember -Function @($public | ForEach-Object { $_.BaseName }) -Alias '*'
}
