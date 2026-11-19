<#
.SYNOPSIS
    Silently uninstalls every installed version of the Zoom Outlook Plugin.

.DESCRIPTION
    Reads the 64-bit and 32-bit (Wow6432Node) HKLM Uninstall keys and builds an
    inventory of installed programs (updates, hotfixes and service packs excluded).
    Every entry whose DisplayName matches *Zoom Outlook Plugin* and whose version is
    not exactly $KeepVersion (empty keeps none) is uninstalled with
    msiexec.exe /x <ProductCode> /qn /norestart and a verbose MSI log at
    C:\DesktopSupportTools\Logs\Remove_Zoom_Outlook_Plugin_<Version>_<StartTime>.wil.
    The product code is taken from an UninstallString of the form "MsiExec.exe /X{...}".
    An entry whose UninstallString is not an MsiExec command gets no product code but is
    still passed to msiexec.exe /x, so that entry is not removed.
    Exit codes 0, 3010 and 1641 are reported as success or restart required; any other
    exit code takes an error branch meant to stop the script.

    A transcript is written to
    C:\DesktopSupportTools\Logs\Remove_All_Zoom_Outlook_Plugin_Installations_<StartTime>.log
    (the folder is created if needed). Progress is written with Write-Host. When nothing
    matches, writes the warning "Zoom Outlook Plugin is not installed on this computer."

    The script ends with [Environment]::Exit, using the exit code of the last uninstaller
    (0 when nothing was uninstalled), which closes the PowerShell host. The application
    name and $KeepVersion are variables at the top of the script.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Remove_All_Versions_of_Zoom_Outlook_Plugin-Package.ps1

    Removes the Zoom Outlook Plugin and returns msiexec's exit code.

.NOTES
    Requires administrator rights. Intended to run as a software-deployment package in
    its own process, because the script exits the host when done. Windows PowerShell 5.1.
    Close Outlook first so the plugin files are not in use.
#>

#User Modifiable Variables

#Application Name:
#    Note that this script will search within the DisplayName property for the name of the application.
#    (ex: 'Techsmith *SnagIT*', 'Cisco *AnyConnect* Diagnostics and Reporting Tool', '*Computrace*')
$Application = 'Zoom Outlook Plugin'
$FriendlyApplication = ''

#Product Version
#    Note that this script will search starting with the leftmost part of the DisplayVersion property for the version of the application.
#    (ex: '18.' will match '18.1.0', '15' will not match '14.0.15', $null will match any version)
$KeepVersion = ''

# DO NOT MODIFY BELOW THIS LINE
If (!($FriendlyApplication)) {$FriendlyApplication = $Application}

$StartTime = Get-Date -format "yyyy-MM-dd HH.mm tt"
$LogFile = ('C:\DesktopSupportTools\Logs\Remove_All_' + $FriendlyApplication `
        + '_Installations_' + $StartTime + '.log').Replace(" ", "_")
$ErrorActionPreference = "SilentlyContinue"
Stop-Transcript | Out-Null
$ErrorActionPreference = "Continue"
If (!(Test-Path -Path "C:\DesktopSupportTools\Logs\")) { 
    New-Item -ItemType Directory -Path "C:\DesktopSupportTools\Logs\"
}
Start-Transcript -Path "$LogFile"
Write-Host "Script Started $($StartTime)"


$Installs = @()
$Paths = @("SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall", `
        "SOFTWARE\\Wow6432node\\Microsoft\\Windows\\CurrentVersion\\Uninstall"
)

ForEach ($Path in $Paths) {
    Write-Verbose  "Checking Path: $Path"

    #  Create an instance of the Registry Object and open the HKLM base key
    Try {
        $reg = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')
    }
    Catch {
        Write-Error $_
        Continue
    }

    #  Drill down into the Uninstall key using the OpenSubKey Method
    Try {
        $regkey = $reg.OpenSubKey($Path)

        # Retrieve an array of string that contain all the subkey names
        $subkeys = $regkey.GetSubKeyNames()

        # Open each Subkey and use GetValue Method to return the required  values for each
        ForEach ($key in $subkeys) {
            Write-Verbose "Key: $Key"
            $thisKey = $Path + "\\" + $key

            Try {
                $thisSubKey = $reg.OpenSubKey($thisKey)

                # Prevent Objects with empty DisplayName
                $DisplayName = $thisSubKey.getValue("DisplayName")

                If ($DisplayName -AND $DisplayName -notmatch '^Update  for|rollup|^Security Update|^Service Pack|^HotFix') {
                    $Date = $thisSubKey.GetValue('InstallDate')

                    If ($Date) {
                        Try {
                            $Date = [datetime]::ParseExact($Date, 'yyyyMMdd', $Null)
                        }
                        Catch {
                            Write-Warning "$($Computer): $_ <$($Date)>"
                            $Date = $Null
                        }
                    }

                    # Create New Object with empty Properties
                    $Publisher = Try {
                        $thisSubKey.GetValue('Publisher').Trim()
                    }
                    Catch {
                        $thisSubKey.GetValue('Publisher')
                    }

                    $Version = Try {
                        #Some weirdness with trailing [char]0 on some strings
                        $thisSubKey.GetValue('DisplayVersion').TrimEnd(([char[]](32, 0)))
                    }
                    Catch {
                        $thisSubKey.GetValue('DisplayVersion')
                    }

                    $UninstallString = Try {
                        $thisSubKey.GetValue('UninstallString').Trim()
                    }
                    Catch {
                        $thisSubKey.GetValue('UninstallString')
                    }

                    $ProductID = Try {
                        If ($UninstallString.StartsWith('Msiexec.exe /', "CurrentCultureIgnoreCase")) {
                            $UninstallString -Replace 'MsiExec.exe \/\w+'
                        }
                        ELSE {
                            $null
                        }
                    }
                    Catch {
                        $Null
                    }

                    $InstallLocation = Try {
                        $thisSubKey.GetValue('InstallLocation').Trim()
                    }
                    Catch {
                        $thisSubKey.GetValue('InstallLocation')
                    }

                    $InstallSource = Try {
                        $thisSubKey.GetValue('InstallSource').Trim()
                    }
                    Catch {
                        $thisSubKey.GetValue('InstallSource')
                    }

                    $HelpLink = Try {
                        $thisSubKey.GetValue('HelpLink').Trim()
                    }
                    Catch {
                        $thisSubKey.GetValue('HelpLink')
                    }

                    $Object = [pscustomobject]@{
                        DisplayName     = $DisplayName
                        Version         = $Version
                        InstallDate     = $Date
                        Publisher       = $Publisher
                        UninstallString = $UninstallString
                        ProductID       = $ProductID
                        InstallLocation = $InstallLocation
                        InstallSource   = $InstallSource
                        HelpLink        = $HelpLink
                        EstimatedSizeMB = [decimal]([math]::Round(($thisSubKey.GetValue('EstimatedSize') * 1024) / 1MB, 2))
                    }

                    $Object.pstypenames.insert(0, 'System.Software.Inventory')
                    $Installs += $Object
                }

            }
            Catch {
                Write-Warning "$Key : $_"
            }
        }
    }
    Catch {

    }
    $reg.Close()
}
If (!$KeepVersion) { $KeepVersion = '0' }

$Uninstalls = $Installs | `
    Where-Object {$_.DisplayName -like "*$Application*" `
        -and $_.Version -ne "$KeepVersion"}

If ($Uninstalls.DisplayName.count -gt 0) {
    Write-Host "$FriendlyApplication is Installed"

    #Loop through the installed Application products.
    foreach ($Uninstall in $Uninstalls) {
        Write-Host "Uninstalling $($Uninstall.DisplayName)..."
        $MSILogFile = "C:\DesktopSupportTools\Logs\Remove_$($Application) $($Uninstall.Version) $($StartTime).wil"

        $Arguments = @(
            "/x "
            $Uninstall.ProductID
            " /qn /norestart /l*v "
            $MSILogFile.Replace(" ", "_")
            )

        $Uninstaller = start-process -FilePath 'msiexec.exe' -ArgumentList $Arguments `
            -WindowStyle Hidden -Wait -PassThru
        
        #Hack required for rare instances where -Wait or WaitForExit() doesn't actually wait.
        #$Handles = $Uninstaller.Handle

        switch ($Uninstaller.ExitCode) {
            3010 {
                Write-Host "Restart required for $($Uninstall.DisplayName)."
            }
            1641 {
                Write-Warning "Restart required for $($Uninstall.DisplayName)."
                If ($Global:shuttingDown) { shutdown -a }
            }
            0 {
                Write-Host "Uninstall of $($Uninstall.DisplayName) succesfully completed."
            }
            default {
                Write-Error "Unable to remove $($Uninstall.DisplayName)" `
                    -Exception [Environment]::Exit($Uninstaller.ExitCode) `
                    -ErrorAction Stop
            }            
        }
    }
}
elseIf ($Uninstalls.count -eq 0) {
    Write-Warning "$FriendlyApplication is not installed on this computer."
}

#Stop Transcription Logging
Write-Host "Script Complete $(Get-Date -Format "HH:mm tt")"
Stop-Transcript

$SystemEvents = [Microsoft.Win32.SystemEvents]
Register-ObjectEvent -InputObject $SystemEvents -EventName "SessionEnding" -Action {
    "Shutdown or Logoff detected."; `
        Get-Process -Name Powershell `
        | Stop-Process -Force}

[Environment]::Exit($Uninstaller.ExitCode)
