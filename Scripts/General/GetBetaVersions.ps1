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
