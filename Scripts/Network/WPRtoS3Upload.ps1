<#
.SYNOPSIS
    Intended to install Windows Performance Recorder, record a 5-minute trace, zip it and upload the zip to an S3 bucket.

.DESCRIPTION
    Creates $env:TEMP\WPR if needed, downloads an MSI from https://aka.ms/wpr/wpr_x64.msi
    into it and installs it silently with msiexec. It then runs
    wpr.exe /start $env:TEMP\output.etl with buffer, file-mode and /duration 300
    options and waits for it to exit.

    Next it zips $env:TEMP\output.etl into WPR-<ComputerName>-<Timestamp>.zip in the
    current directory (Compress-Archive), uploads the zip with Write-S3Object (private
    canned ACL, the zip name as the key, default AWS region), and deletes the .etl and
    the zip. The downloaded MSI is left in $env:TEMP\WPR. The timestamp is local time
    although it ends in Z.

    The wpr.exe arguments do not follow the documented WPR syntax (/start takes a
    recording profile, and a trace is saved with /stop <file>; the script never calls
    /stop), so the .etl file may not be created and the later steps would then fail.
    The bucket name is a placeholder variable at the top of the script that must be
    edited. Outputs the folder object when it creates $env:TEMP\WPR.

.EXAMPLE
    .\WPRtoS3Upload.ps1

    Installs WPR, attempts a 5-minute recording and uploads the result to the bucket
    set in the script.

.NOTES
    Requires administrator rights (MSI install and kernel tracing), network access to
    aka.ms and Amazon S3, the AWS Tools for PowerShell module (Write-S3Object) and AWS
    credentials available to it (credential profile, environment variables or instance
    role); the script stores no credentials. Works in Windows PowerShell 5.1 and
    PowerShell 7.
#>
# Define variables
$downloadUrl = "https://aka.ms/wpr/wpr_x64.msi"
$tempFolder = "$env:TEMP\WPR"
$outputFile = "$env:TEMP\output.etl"
$bucketName = "your-bucket-name"

# Get current date/time in GMT
$dateTime = Get-Date -Format "yyyy-MM-ddTHH-mm-ssZ"

# Add computer name and date/time to the zip file name
$compressedFile = "WPR-$env:COMPUTERNAME-$dateTime.zip"

# Create temp folder if it doesn't exist
if (!(Test-Path -Path $tempFolder -PathType Container)) {
    New-Item -ItemType Directory -Path $tempFolder
}

# Download and install Windows Performance Recorder
Invoke-WebRequest -Uri $downloadUrl -OutFile "$tempFolder\wpr_x64.msi"
Start-Process msiexec.exe -ArgumentList "/i $tempFolder\wpr_x64.msi /quiet" -Wait

# Start recording for 5 minutes
Start-Process wpr.exe -ArgumentList "/start $outputFile /minbuffers 512 /maxfile 1024 /filemode 1 /duration 300" -Wait

# Compress the ETL file
Compress-Archive -Path $outputFile -DestinationPath $compressedFile

# Upload to S3 with private ACL
$key = Split-Path -Path $compressedFile -Leaf
Write-S3Object -BucketName $bucketName -File $compressedFile -Key $key -CannedACL "private"

# Delete artifacts
Remove-Item $outputFile
Remove-Item $compressedFile