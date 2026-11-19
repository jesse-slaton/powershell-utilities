<#
.SYNOPSIS
    Unfinished: downloads the Microsoft 365 Apps Beta Channel update history page and parses it with AngleSharp.

.DESCRIPTION
    Loads AngleSharp.dll from a hard-coded folder (writing an error if the file is not
    there), downloads
    https://learn.microsoft.com/en-us/officeupdates/update-history-beta-channel with
    Invoke-WebRequest, and parses the HTML into an AngleSharp document stored in
    $document. Nothing is extracted or written to the output; the script stops after
    parsing. Read-only. When dot-sourced, $document is left in the session for further
    work.

.EXAMPLE
    . .\GetBetaVersions.ps1
    $document.Title

    Dot-sources the script, then reads the parsed page's title from $document.

.NOTES
    Requires AngleSharp.dll at the hard-coded path in the script (a personal OneDrive
    folder; edit it for your system) and network access to learn.microsoft.com. If the
    DLL is missing, the AngleSharp type cannot be created and the script fails. No
    admin rights needed.
#>

# Use $PSScriptRoot to get the script's directory
$angleSharpDllPath = Join-Path -Path "D:\OneDrive - Doxazo\Documents\PowerShell\Scripts\O365Version" -ChildPath "AngleSharp.dll"

# Check if the path exists before attempting to load
if (Test-Path $angleSharpDllPath) {
    Add-Type -Path $angleSharpDllPath
} else {
    Write-Error "AngleSharp.dll not found at path: $angleSharpDllPath"
}

# URL of the web page you want to parse
$url = "https://learn.microsoft.com/en-us/officeupdates/update-history-beta-channel"

# Fetch the web page content
$pageContent = Invoke-WebRequest -Uri $url

# Ensure you have the HTML content in a variable, e.g., $htmlContent
$htmlContent = $pageContent.Content

# Create an instance of the HTML parser
$parser = [AngleSharp.Html.Parser.HtmlParser]::new()

# Parse the HTML content
$document = $parser.ParseDocument($htmlContent)
