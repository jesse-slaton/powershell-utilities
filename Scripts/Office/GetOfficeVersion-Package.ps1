<#
.SYNOPSIS
    Looks up the installed Office Click-to-Run build in an online version list and saves the match as CLIXML.

.DESCRIPTION
    Downloads the full Office version list as JSON from
    https://functions.office365versions.com/api/getjson?name=all and converts each entry's
    build and fullBuild to [version] and its releaseDate to [datetime] (format
    'yyyy MMM dd').

    Reads VersionToReport from HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration
    and keeps the entries whose fullBuild equals it, selecting Version, Channel, Build,
    ReleaseDate and EndOfSupportDate. The result is exported to FilteredVersions.xml
    (Export-Clixml) in the current directory, compressed to FilteredVersions.zip in the
    current directory, and the zip is then expanded back into the current directory.
    Writes no pipeline output.

    Compress-Archive and Expand-Archive are called without -Force or -Update, so when
    FilteredVersions.zip or FilteredVersions.xml already exist those steps write errors.

.EXAMPLE
    .\GetOfficeVersion-Package.ps1

    Writes FilteredVersions.xml and FilteredVersions.zip to the current directory.
    Read them back with Import-Clixml -Path .\FilteredVersions.xml.

.NOTES
    Requires internet access to functions.office365versions.com (a third-party site),
    PowerShell 5.0 or later (Compress-Archive and Expand-Archive), write access to the
    current directory, and Office Click-to-Run installed. Reads HKLM without
    administrator rights.
#>
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
