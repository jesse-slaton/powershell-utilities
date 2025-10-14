# Fetch the JSON data from the URL
$response = Invoke-WebRequest -Uri "https://functions.office365versions.com/api/getjson?name=all" -UseBasicParsing
$AllVersions = ($response.Content | ConvertFrom-Json).data

# Process and type-cast the data
$AllVersions | ForEach-Object {
    $_.build = [version] $_.build
    $_.fullBuild = [version] $_.fullBuild
    $_.releaseDate = [datetime]::ParseExact($_.releaseDate, 'yyyy MMM dd', $null)
}

# Filter for specific version
[version] $VersiontoReport = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -Name "VersionToReport").VersionToReport
$FilteredVersions = $AllVersions | Where-Object { $_.fullBuild -eq $VersiontoReport } | Select-Object -Property Version, Channel, Build, ReleaseDate, EndOfSupportDate

# Export the filtered versions to a CLIXML file
$FilteredVersions | Export-Clixml -Path "./FilteredVersions.xml"

# Optionally compress the CLIXML file
Compress-Archive -Path "./FilteredVersions.xml" -DestinationPath "./FilteredVersions.zip"

# To re-import and decompress:
Expand-Archive -Path "./FilteredVersions.zip" -DestinationPath "./"
#$ImportedVersions = Import-Clixml -Path "./FilteredVersions.xml"
