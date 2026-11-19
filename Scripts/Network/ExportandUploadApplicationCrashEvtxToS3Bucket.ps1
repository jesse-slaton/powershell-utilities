<#
.SYNOPSIS
    Intended to export the last 7 days of Application crash events, zip them and upload the zip to an S3 bucket.

.DESCRIPTION
    Imports the AWSPowerShell module, then reads Application log entries from the last
    7 days with instance IDs 1000 and 1001 (Get-EventLog) and saves them with
    Export-Clixml to $env:TEMP\ApplicationCrashLog.evtx. Despite the extension, that
    file is PowerShell CLIXML, not an event log (.evtx) file.

    It then calls [System.IO.Compression.ZipFile]::CreateFromDirectory on that file to
    build a zip in $env:TEMP, uploads the zip with Write-S3Object (private canned ACL)
    using the zip name as the object key, and deletes both files. CreateFromDirectory
    expects a folder, not a file, so as written the zip step fails, and the upload and
    the zip cleanup then fail too.

    The bucket name and region are set in variables at the top of the script; the
    bucket is a placeholder that must be edited. The zip name is meant to include the
    computer name and a timestamp, but "$env:COMPUTERNAME_" is read as an (empty)
    variable named COMPUTERNAME_, so the computer name is missing. Produces no output
    on success.

.EXAMPLE
    .\ExportandUploadApplicationCrashEvtxToS3Bucket.ps1

    Runs the export and upload with the bucket and region set in the script.

.NOTES
    Requires the AWSPowerShell module (AWS Tools for PowerShell) and AWS credentials
    available to it (credential profile, environment variables or instance role); the
    script stores no credentials. Needs network access to Amazon S3. Uses Get-EventLog,
    which exists only in Windows PowerShell 5.1. On 5.1 the
    System.IO.Compression.FileSystem assembly may also need to be loaded first.
#>
# Import the AWS Tools for PowerShell module
Import-Module AWSPowerShell

# Set the region of your S3 bucket
$region = "us-east-1"

# Set the name of your S3 bucket
$bucketName = "your-bucket-name"

# Set the path where you want to save the exported and compressed event log
$logPath = "$env:TEMP\ApplicationCrashLog_$env:COMPUTERNAME_$(Get-Date -UFormat '%Y%m%dT%H%M%Szzz')GMT.zip"

# Export the Application crash events to a .evtx file
Get-EventLog -LogName Application -After (Get-Date).AddDays(-7) -InstanceId 1000,1001 | Export-Clixml -Path "$env:TEMP\ApplicationCrashLog.evtx"

# Compress the .evtx file into a .zip file
[System.IO.Compression.ZipFile]::CreateFromDirectory("$env:TEMP\ApplicationCrashLog.evtx", $logPath)

# Upload the compressed event log to your S3 bucket with private ACL
$key = Split-Path -Path $logPath -Leaf
Write-S3Object -BucketName $bucketName -Key $key -File $logPath -Region $region -CannedACL private

# Remove artifacts
Remove-Item "$env:TEMP\ApplicationCrashLog.evtx"
Remove-Item $logPath
