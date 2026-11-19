<#
.SYNOPSIS
    Outputs whether the installed Office Click-to-Run is 32-bit or 64-bit.

.DESCRIPTION
    Opens the 64-bit view of HKLM and reads the Platform value from
    SOFTWARE\Microsoft\Office\ClickToRun\Configuration. Outputs "32-bit" for x86,
    "64-bit" for x64, or "Unknown Office Platform: <value>" for anything else.

    When the Platform value is missing it outputs "The Platform value is not set. Unable
    to determine Office bitness."; when the Configuration key is missing it outputs
    "Office Click-to-Run configuration is not found. Office may not be installed.". An
    exception is output as "An error occurred: <message>". Read-only. The script defines
    the Get-OfficeClickToRunBitness function and calls it once.

.EXAMPLE
    .\GetOffice365Bitness.ps1

    64-bit

.NOTES
    None. Reads HKLM without administrator rights. Only Click-to-Run installations are
    detected; MSI-based Office is reported as not found.
#>


function Get-OfficeClickToRunBitness {
    try {
        # Open the 64-bit view of the Local Machine registry hive directly
        $regKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)

        # Define the path to the Office Click-to-Run configuration in the registry
        $regPath = "SOFTWARE\Microsoft\Office\ClickToRun\Configuration"

        # Open the registry subkey
        $officeReg = $regKey.OpenSubKey($regPath)

        if ($officeReg -ne $null) {
            # Read the value for the Platform
            $officePlatform = $officeReg.GetValue("Platform")
            $officeReg.Close()

            if ($officePlatform -ne $null) {
                # Determine Office bitness based on the Platform value
                switch ($officePlatform) {
                    "x86" { Write-Output "32-bit" }
                    "x64" { Write-Output "64-bit" }
                    Default { Write-Output "Unknown Office Platform: $officePlatform" }
                }
            }
            else {
                Write-Output "The Platform value is not set. Unable to determine Office bitness."
            }
        }
        else {
            Write-Output "Office Click-to-Run configuration is not found. Office may not be installed."
        }
    }
    catch {
        Write-Output "An error occurred: $_"
    }
}

# Execute the function
Get-OfficeClickToRunBitness
