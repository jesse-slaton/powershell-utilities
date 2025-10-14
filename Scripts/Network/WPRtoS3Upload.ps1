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