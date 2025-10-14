# Function to get the Office 365 Channel
function Get-Office365Channel {
    try {
        # Open the 64-bit view of the Local Machine registry hive directly
        $regKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)

        # Define the path to the Office Click-to-Run configuration in the registry
        $regPath = "SOFTWARE\Microsoft\Office\ClickToRun\Configuration"

        # Open the registry subkey
        $officeReg = $regKey.OpenSubKey($regPath)

        if ($officeReg -ne $null) {
            # Read the value for the Office 365 Channel
            $officeChannel = $officeReg.GetValue("CDNBaseUrl")
            $officeReg.Close()

            # Translate the CDNBaseUrl to a user-friendly channel name
            switch ($officeChannel) {
                "http://officecdn.microsoft.com/pr/55336b82-a18d-4dd6-b5f6-9e5095c314a6" { "Monthly Enterprise Channel" }
                "http://officecdn.microsoft.com/pr/492350f6-3a01-4f97-b9c0-c7c6ddf67d60" { "Current Channel" }
                "http://officecdn.microsoft.com/pr/64256afe-f5d9-4f86-8936-8840a6a4f5be" { "Current Channel (Preview)" }
                "http://officecdn.microsoft.com/pr/7ffbc6bf-bc32-4f92-8982-f9dd17fd3114" { "Semi-Annual Enterprise Channel" }
                "http://officecdn.microsoft.com/pr/b8f9b850-328d-4355-9145-c59439a0c4cf" { "Semi-Annual Enterprise Channel (Preview)" }
                "http://officecdn.microsoft.com/pr/5440fd1f-7ecb-4221-8110-145efaa6372f" { "Beta Channel" }
                Default { "Unknown Channel - CDNBaseUrl: $officeChannel" }
            }
        }
        else {
            Write-Output "Office 365 is not installed or the registry path is incorrect."
        }
    }
    catch {
        Write-Output "An error occurred: $_"
    }
}

# Execute the function
Get-Office365Channel
