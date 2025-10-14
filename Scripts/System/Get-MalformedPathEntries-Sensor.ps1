<#
.SYNOPSIS
    Analyzes the PATH environment variable for malformed entries.

.DESCRIPTION
    This function checks the PATH environment variable for common issues, such as:
    - Unbalanced quotes
    - Incorrect semicolons after the drive letter
    - Duplicate entries
    - Blank or empty entries
    - Non-existent directories

    It provides suggestions for fixing each issue.

.EXAMPLE
    Get-MalformedPathEntries
    Analyzes the current PATH variable and reports errors and suggested fixes.

.EXAMPLE
    $malformedEntries = Get-MalformedPathEntries
    $malformedEntries | ForEach-Object { "$($_.Entry)|$($_.Issue)|$($_.SuggestedEntry)" }
    Formats the output as pipe-delimited entries without spaces between the pipes.

#>

function Get-MalformedPathEntries {
    [CmdletBinding()]
    param ()

    try {
        # Get the PATH variable as a raw string
        $pathRaw = [System.Environment]::GetEnvironmentVariable('PATH')

        if (-not $pathRaw) {
            throw "The PATH environment variable is empty or not set."
        }

        # Remove leading/trailing semicolons and split on semicolons outside quotes
        $pathRaw = $pathRaw.Trim(';')
        $pathEntries = [regex]::Split($pathRaw, '(?<!")\;(?!")')

        # Track seen entries to detect duplicates
        $seenPaths = @{}
        $results = @()

        foreach ($entry in $pathEntries) {
            $suggestedEntry = $entry
            $issue = $null

            # Check for unbalanced double-quotes (a single double-quote is present)
            $quoteCount = ($entry -split '"').Count - 1
            if ($quoteCount % 2 -ne 0) {
                $suggestedEntry = $entry -replace '"', ''  # Suggest removing unbalanced quotes
                $issue = 'Unbalanced double-quotes, suggest removal'
            }

            # Check for semicolon directly after the drive letter (e.g., C;\path)
            if ($entry -match '^[A-Z]:\\;') {
                # Attempt to fix the path and test if the corrected path exists
                $correctedPath = $entry -replace ':\;', ':\'
                if (Test-Path $correctedPath) {
                    $suggestedEntry = $correctedPath
                    $issue = 'Incorrect semicolon after drive letter, suggest valid path'
                } else {
                    $suggestedEntry = 'Delete'
                    $issue = 'Incorrect semicolon after drive letter, no valid path found'
                }
            }

            # Check for empty or blank entries
            if ([string]::IsNullOrWhiteSpace($entry)) {
                $issue = 'Empty or blank entry'
                $suggestedEntry = 'Delete'
            }

            # Check for duplicates
            if ($seenPaths.ContainsKey($entry)) {
                $issue = 'Duplicate entry'
                $suggestedEntry = 'Delete'
            } else {
                $seenPaths[$entry] = $true
            }

            # Check if the path exists
            if (-not [System.IO.Directory]::Exists($entry.Trim('"')) -and $entry -notmatch '^[A-Z]:\\$') {
                $issue = 'Non-existent directory'
                $suggestedEntry = 'Delete'
            }

            # Collect the result if any issue was found
            if ($issue) {
                $results += [PSCustomObject]@{
                    Entry          = $entry
                    Issue          = $issue
                    SuggestedEntry = $suggestedEntry
                }
            }
        }

        return $results

    } catch {
        Write-Error "An error occurred while analyzing the PATH variable: $_"
    }
}

# Execute the function and format the output as pipe-delimited without spaces
$malformedEntries = Get-MalformedPathEntries
$malformedEntries | ForEach-Object {
    "$($_.Entry)|$($_.Issue)|$($_.SuggestedEntry)"
}