Get-ChildItem "c:\users\*\appdata\local\Google\Chrome\User Data\Default\Extensions\*\*\manifest.json" -ErrorAction SilentlyContinue | ForEach-Object {
    $path = $_.FullName
    $_.FullName -match 'users\\(.*?)\\appdata' | Out-Null
    Get-Content $_.FullName -Raw | ConvertFrom-Json #| Select-Object  @{n = 'User'; e = { $Matches[1] } }, Name, Version, @{n = 'Path'; e = { $path } }
}
