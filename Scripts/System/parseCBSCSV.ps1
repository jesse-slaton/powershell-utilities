<#
.SYNOPSIS
    Converts C:\support\logs\parsedcbs.csv into pipe-delimited lines with the age of each entry in days.

.DESCRIPTION
    Imports C:\support\logs\parsedcbs.csv, which must have the columns DateTime,
    LogLevel, Source and ResultString. For each row it parses DateTime with the current
    culture, computes the whole days between that time and now, removes double quotes
    from the other fields, and outputs one string per row:

        <DaysAgo>|<LogLevel>|<Source>|<ResultString>

    If the file does not exist it outputs "CSV file '<path>' does not exist." Read-only.

.EXAMPLE
    .\parseCBSCSV.ps1

    <DaysAgo>|<LogLevel>|<Source>|<ResultString>

.NOTES
    None. The input path is hard-coded; the CSV is produced by a separate CBS log
    parsing step.
#>

# PowerShell Script to parse the parsedcbs.csv file and output the results in "|" format

# Define the input CSV file path
$inputCsvFilePath = "C:\support\logs\parsedcbs.csv"

# Check if the input CSV file exists
if (Test-Path -Path $inputCsvFilePath) {
    # Import the CSV file and skip the header
    $csvContent = Import-Csv -Path $inputCsvFilePath

    # Get the current date and time
    $now = Get-Date

    # Iterate through the CSV content and output the results in "|" format, removing any double quotes
    $csvContent | ForEach-Object {
        # Convert the datetime value to a datetime object
        $dateTime = [DateTime]::Parse($_.DateTime)

        # Calculate the number of days between the last ran date and the current date
        $lastRanDaysAgo = ($now - $dateTime).Days  -replace '"', ''
        $logLevel = $_.LogLevel -replace '"', ''
        $source = $_.Source -replace '"', ''
        $resultString = $_.ResultString -replace '"', ''

        # Format the output
        $output = "{0}|{1}|{2}|{3}" -f $lastRanDaysAgo, $logLevel, $source, $resultString
        Write-Output $output
    }
} else {
    # Output a user-friendly error message if the input CSV file doesn't exist
    Write-Output "CSV file '$inputCsvFilePath' does not exist."
}
