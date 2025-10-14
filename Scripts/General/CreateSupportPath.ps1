<#
.SYNOPSIS
    This PowerShell script creates a Logs directory under the Support directory and compresses it if it doesn't exist.

.DESCRIPTION
    The script defines a function named CreateLogsPath that creates the Logs directory and compresses it.
    It initializes variables within the function to reduce global scope pollution.
    Finally, it checks if the Support directory exists and if the Logs directory exists, and creates them if needed.

.NOTES
    Author: Jesse Slaton
    Date: 2023-04-20

.EXAMPLE
    To run this script, open a PowerShell console and navigate to the directory containing the script.
    Then run it by typing:
    .\ScriptName.ps1
#>

# Define the CreateLogsPath function to create and compress the Logs directory
Function CreateLogsPath {
    Param (
        [string]$SupportPath
    )
    
    # Initialize variables
    $LogsPath = "$SupportPath\Logs"
    $WQL = "Select * from Win32_Directory WHERE Name = '$LogsPath'"

    # Create the Logs directory
    $Null = New-Item -ItemType Directory -Path $LogsPath

    # Compress the Logs directory
    $EscapedWQL = $WQL.Replace('\','\\')
    $Null = Invoke-CimMethod -Query $EscapedWQL -Namespace root/CIMV2 -MethodName Compress
}

# Initialize the SupportPath variable
$SupportPath = "C:\Support"

# Check if the Support directory exists and create it if necessary
If (-not (Test-Path -Path $SupportPath)) {
    $Null = New-Item -ItemType Directory -Path $SupportPath
}

# Check if the Logs directory exists, and create and compress it if necessary
If (-not (Test-Path -Path "$SupportPath\Logs")) {
    CreateLogsPath -SupportPath $SupportPath
}
