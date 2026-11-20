<#
.SYNOPSIS
    Reports whether exactly four matching Hyland component entries are installed at a supported
    20.3 build.

.DESCRIPTION
    Lists the applications in the HKLM Uninstall registry keys whose publisher matches
    *Hyland*, counts those whose name matches Virtual Print, Office 2016, Web ActiveX or
    Unity and whose version matches 20.3.2.1000 or 20.3.7376.943 (regular-expression
    matches), and writes $True when the count is exactly 4, otherwise $False. Entries are
    counted, not distinct components: duplicates can make up the four, and a fifth match
    gives $False. Read-only.

.EXAMPLE
    .\HylandCompliance-Package.ps1

    Writes True on a computer with the complete Hyland rollout, otherwise False.

.NOTES
    Requires Windows. Reads HKLM only, so no admin rights or modules are needed. Per-user
    (HKCU) installs are not counted.
#>


Function Get-InstalledApplications {
    <#
    .SYNOPSIS
        Lists installed applications from the HKLM Uninstall registry keys.
    .DESCRIPTION
        Reads the 64-bit and 32-bit (Wow6432Node) Uninstall keys under HKLM and returns one
        System.Software.Inventory object per entry that has a DisplayName (Name, Version,
        InstallDate, Publisher, UninstallString, ProductID, InstallLocation, InstallSource,
        Hidden, HelpLink, EstimatedSizeMB). Entries are skipped when the name starts with
        Security Update, Service Pack or HotFix, contains "rollup", or contains KB followed by
        a digit. The "Update for" filter has two spaces in its pattern, so most "Update for"
        entries are listed. Every parameter given narrows the result, and all of them must
        match. Read-only.
    .PARAMETER Name
        Display name to match. Wildcards are supported.
    .PARAMETER VersionNumber
        Exact DisplayVersion to match.
    .PARAMETER MajorVersion
        First dotted part of DisplayVersion to match (0 to 999).
    .PARAMETER PublisherName
        Publisher to match. Wildcards are supported.
    .PARAMETER Hidden
        $true to return only entries marked SystemComponent, $false to return only the others.
    .EXAMPLE
        Get-InstalledApplications -Name '*AnyConnect*'
    .EXAMPLE
        Get-InstalledApplications -PublisherName '*Hyland*' -MajorVersion 20
    .NOTES
        Requires Windows. Reads HKLM only, which needs no admin rights; per-user (HKCU)
        installs are not listed.
    #>
    [CmdletBinding()]
    param (
        # Display name (supports wildcards)
        [Parameter(
            Position = 0
        )]
        [SupportsWildcards()][string]
        $Name,
        [Parameter(
        )]
        [string]
        $VersionNumber,
        [Parameter(
        )]
        [ValidateRange(0, 999)]
        [int]
        $MajorVersion,
        [Parameter(
        )]
        [SupportsWildcards()][string]
        $PublisherName,
        [Parameter(
        )]
        [bool]
        $Hidden
    )
    # build conditional where-object expression
    if ($PSBoundParameters.Count -gt 0) {
        $conditions = @{
            Name          = '($_.Name -like $Name)'
            VersionNumber = '($_.Version -eq $VersionNumber)'
            MajorVersion  = '(($null -ne $_.Version) -and ($_.Version.split(''.'')[0] -eq $MajorVersion))'
            PublisherName = '($_.Publisher -like $PublisherName)'
            Hidden        = '($_.Hidden -eq $Hidden)'
        }
        $x = foreach ($pkey in $PSBoundParameters.Keys) {
            $conditions.$pKey
        }
        $expression = $x -join ' -and '
    }
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
                    If ($DisplayName `
                            -AND $DisplayName -notmatch '^Update  for|rollup|^Security Update|^Service Pack|^HotFix' `
                            -AND $DisplayName -notlike '*KB[0-9]*') {
                        $Date = $thisSubKey.GetValue('InstallDate')
                        If ($Date) {
                            Try {
                                $tempdate = [datetime]::ParseExact($Date, 'yyyyMMdd', $Null)
                                $Date = '{0:R}' -f (Get-Date -Date $tempdate)
                            }
                            Catch {
                                #Write-Warning "$($Computer): $_ <$($Date)>"
                                $Date = $Null
                            }
                        }
                        # Create New Object with empty Properties
                        $Publisher = Try {
                            if ($null -eq $thisSubKey.GetValue('Publisher')) {
                                'N/A'
                            }
                            else {
                                $thisSubKey.GetValue('Publisher').Trim()
                            }
                        }
                        Catch {
                            $thisSubKey.GetValue('Publisher')
                        }
                        $Version = Try {
                            if ($null -eq $thisSubKey.GetValue('DisplayVersion')) {
                                'N/A'
                            }
                            else {
                                #Some weirdness with trailing [char]0 on some strings
                                $thisSubKey.GetValue('DisplayVersion').TrimEnd(([char[]](32, 0)))
                            }
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
                        $SysComponent = Try {
                            If ($null -eq $thisSubKey.GetValue('SystemComponent')) {
                                $False
                            }
                            Else {
                                [bool]$thisSubKey.GetValue('SystemComponent').Trim()
                            }
                        }
                        Catch {
                            [bool]$thisSubKey.GetValue('SystemComponent')
                        }
                        $Object = [pscustomobject]@{
                            Name            = $DisplayName
                            Version         = $Version
                            InstallDate     = $Date
                            Publisher       = $Publisher
                            UninstallString = $UninstallString
                            ProductID       = $ProductID
                            InstallLocation = $InstallLocation
                            InstallSource   = $InstallSource
                            Hidden          = $SysComponent
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
    If ($null -eq $expression) {
        $Installs
    }
    Else {
        $Installs | Where-Object { (Invoke-Expression $expression) }
    }
}

#Check if all four components of the Hyland Rollout are installed and up to v20
$HylandCount = (Get-InstalledApplications -PublisherName '*Hyland*' | Where-Object { $_.Name -match 'Virtual Print|Office 2016|Web ActiveX|Unity' -and $_.version -match '20.3.2.1000|20.3.7376.943' }).count
Switch ($HylandCount) {
    4 { $True }
    default { $False }
}
