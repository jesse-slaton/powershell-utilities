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
