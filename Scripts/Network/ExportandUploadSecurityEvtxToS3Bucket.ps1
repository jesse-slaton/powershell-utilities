# Import the AWS Tools for PowerShell module
Import-Module AWSPowerShell

# Set the region of your S3 bucket
$region = "us-east-1"

# Set the name of your S3 bucket
$bucketName = "your-bucket-name"

# Set the path where you want to save the exported and compressed event log
$logPath = "$env:TEMP\SecurityLog_$env:COMPUTERNAME_$(Get-Date -UFormat '%Y%m%dT%H%M%S')GMT.zip"

# Export the security event log to a .evtx file
Get-EventLog -LogName Security -After (Get-Date).AddDays(-7) | Export-Clixml -Path "$env:TEMP\SecurityLog.evtx"

# Compress the .evtx file into a .zip file
[System.IO.Compression.ZipFile]::CreateFromDirectory("$env:TEMP\SecurityLog.evtx", $logPath)

# Upload the compressed event log to your S3 bucket with private ACL
$key = Split-Path -Path $logPath -Leaf
Write-S3Object -BucketName $bucketName -Key $key -File $logPath -Region $region -CannedACL private

# Remove artifacts
Remove-Item "$env:TEMP\SecurityLog.evtx"
Remove-Item $logPath
