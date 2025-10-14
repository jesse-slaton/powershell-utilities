<#
.SYNOPSIS
    Short description
.DESCRIPTION
    Long description
.EXAMPLE
    PS C:\> <example usage>
    Explanation of what the example does
.INPUTS
    Inputs (if any)
.OUTPUTS
    Output (if any)
.NOTES
    General notes
#>
Function Get-InstalledApplications {
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
