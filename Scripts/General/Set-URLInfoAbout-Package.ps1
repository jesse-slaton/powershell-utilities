<#
.SYNOPSIS
    Sets the URLInfoAbout (support link) of installed Forcepoint products to a Forcepoint documentation URL.

.DESCRIPTION
    First counts Win32_Battery instances. Then reads every uninstall entry under
    HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall and
    HKLM\SOFTWARE\Wow6432node\Microsoft\Windows\CurrentVersion\Uninstall (64-bit
    registry view) into inventory objects, skipping entries without a DisplayName and
    those whose DisplayName matches the update, rollup, security update, service pack
    or hotfix patterns. It keeps the entries whose DisplayName contains "Forcepoint"
    and, if there are any, runs New-ItemProperty -Force on each matching uninstall key:

    - no battery: URLInfoAbout = the "Forcepoint DLP Endpoint" 8.5 documents URL
    - one or more batteries: URLInfoAbout = the "Forcepoint Web Security Endpoint" 8.5
      documents URL

    The application name and both URLs are set in variables at the top of the script.
    The objects returned by New-ItemProperty are written to the output. If no
    Forcepoint entry is found, nothing is changed.

.EXAMPLE
    .\Set-URLInfoAbout-Package.ps1

    Updates the support link that Programs and Features shows for Forcepoint.

.NOTES
    Requires administrator rights (writes to HKLM). Uses Get-WmiObject, so Windows
    PowerShell 5.1 only. Named as a package; it takes no package parameters.
#>

$BatteryCount = (Get-WmiObject win32_battery).Count
$Application = 'Forcepoint'
$CombinedURL = 'https://support.forcepoint.com/DocumentsDisplayed?version=8.5&name=Forcepoint%20Web%20Security%20Endpoint'
$DLPURL      = 'https://support.forcepoint.com/DocumentsDisplayed?version=8.5&name=Forcepoint%20DLP%20Endpoint'

#DO NOT MODIFY

[array]$Installs = @()
$Paths = @("SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall", "SOFTWARE\\Wow6432node\\Microsoft\\Windows\\CurrentVersion\\Uninstall")

ForEach ($Path in $Paths) {
    Write-Verbose  "Checking Path: $Path"

    #  Create an instance of the Registry Object and open the HKLM base key
    Try {
        $reg = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')
    } Catch {
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
                        } Catch {
                            Write-Warning "$($Computer): $_ <$($Date)>"
                            $Date = $Null
                        }
                    }

                    # Create New Object with empty Properties
                    $Publisher = Try {
                        $thisSubKey.GetValue('Publisher').Trim()
                    } Catch {
                        $thisSubKey.GetValue('Publisher')
                    }

                    $Version = Try {
                        #Some weirdness with trailing [char]0 on some strings
                        $thisSubKey.GetValue('DisplayVersion').TrimEnd(([char[]](32, 0)))
                    } Catch {
                        $thisSubKey.GetValue('DisplayVersion')
                    }

                    $UninstallString = Try {
                        $thisSubKey.GetValue('UninstallString').Trim()
                    } Catch {
                        $thisSubKey.GetValue('UninstallString')
                    }

                    $ProductID = Try {
                        IF ($UninstallString.StartsWith('Msiexec.exe /',"CurrentCultureIgnoreCase")) {
                            $UninstallString -Replace 'MsiExec.exe \/\w+'
                        } ELSE {
                            $null
                        }
                    } Catch {
                        $Null
                    }

                    $InstallLocation = Try {
                        $thisSubKey.GetValue('InstallLocation').Trim()
                    } Catch {
                        $thisSubKey.GetValue('InstallLocation')
                    }

                    $InstallSource = Try {
                        $thisSubKey.GetValue('InstallSource').Trim()
                    } Catch {
                        $thisSubKey.GetValue('InstallSource')
                    }

                    $URLInfoAbout = Try {
                        $thisSubKey.GetValue('URLInfoAbout').Trim()
                    } Catch {
                        $thisSubKey.GetValue('URLInfoAbout')
                    }
                    $KeyPath = Try {
                        $thisSubKey
                    } Catch {
                        $thisSubKey
                    }


                    $Object = [pscustomobject]@{
                        KeyPath         = $KeyPath.ToString().Replace('HKEY_LOCAL_MACHINE','HKLM:')
                        DisplayName     = $DisplayName
                        Version         = $Version
                        InstallDate     = $Date
                        Publisher       = $Publisher
                        UninstallString = $UninstallString
                        ProductID       = $ProductID
                        InstallLocation = $InstallLocation
                        InstallSource   = $InstallSource
                        URLInfoAbout        = $thisSubKey.GetValue('URLInfoAbout')
                        EstimatedSizeMB = [decimal]([math]::Round(($thisSubKey.GetValue('EstimatedSize') * 1024) / 1MB, 2))
                    }

                    $Object.pstypenames.insert(0, 'System.Software.Inventory')
                    $Installs += $Object
                }

            } Catch {
                Write-Warning "$Key : $_"
            }
        }
    } Catch {

    }
    $reg.Close()
}

[array]$ForcepointInstalls = $Installs | ? {$_.DisplayName -like "*$Application*"}

if ($ForcepointInstalls.count -gt 0) {
    Switch ($BatteryCount) {
        {$_ -eq 0} { New-ItemProperty -Path $ForcepointInstalls.Keypath -Name URLInfoAbout -Value $DLPURL -Force}
        {$_ -ge 1} { New-ItemProperty -Path $ForcepointInstalls.Keypath -Name URLInfoAbout -Value $CombinedURL -Force}
    }
}