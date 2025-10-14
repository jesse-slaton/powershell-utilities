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
