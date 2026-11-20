<#
.SYNOPSIS
    Sensor that compares the installed version of an application with a reference version.

.DESCRIPTION
    Finds installed applications whose display name contains $Application (hard-coded to
    Cisco AnyConnect Secure Mobility Client) in the HKLM Uninstall registry keys, takes the
    one with the highest Version (sorted as a string), compares that version with
    $ReferenceVersion (4.7.02036) using $Operator, and writes one line:
    <result>|<name>|<version>|<operator>|<reference version>. <result> is True or False, or
    Not Found when no application matches. Versions are compared as strings, not as
    [version] values. Read-only.

.EXAMPLE
    .\Test-MIAVC-Sensor.ps1

    Writes a line such as "|Cisco AnyConnect Secure Mobility Client|4.9.01095|Greater than
    or Equal|4.7.02036" (the result field is empty because of the Operator issue in NOTES).

.NOTES
    Requires Windows. Reads HKLM only, so no admin rights or modules are needed. The inputs
    are hard-coded; the commented-out lines show the Tanium ||parameter|| form they came from.
    Known issues, left as they are: the hard-coded Operator 'Greater than or Equal' matches
    no comparison branch (they end in "to"), so the result field is empty; and when no
    application is found, the line is written with an empty name after a null-method error.
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
                                $Date = [datetime]::ParseExact($Date, 'yyyyMMdd', $Null)
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

# [string] $Application = [System.Uri]::UnescapeDataString('||Application||')
# [string] $Operator = [System.Uri]::UnescapeDataString('||Operator||')
# [string] $ReferenceVersion = [System.Uri]::UnescapeDataString('||ReferenceVersion||')

[string] $Application = 'Cisco AnyConnect Secure Mobility Client'
[string] $Operator = 'Greater than or Equal'
[string] $ReferenceVersion = '4.7.02036'

$InstalledApplication = $(Get-InstalledApplications -Name "*$Application*") | Sort-Object -Property Version -Descending | Select-Object -First 1

    If ($InstalledApplication.count -gt 0 ) {
        Switch ($Operator) {
            'Greater than' { $Result = $InstalledApplication.Version -gt $ReferenceVersion }
            'Greater than or Equal to' { $Result = $InstalledApplication.Version -ge $ReferenceVersion }
            'Equal to' { $Result = $InstalledApplication.Version -eq $ReferenceVersion }
            'Less than' { $Result = $InstalledApplication.Version -lt $ReferenceVersion }
            'Less than or Equal to' { $Result = $InstalledApplication.Version -le $ReferenceVersion }
            'Not Equal to' { $Result = $InstalledApplication.Version -ne $ReferenceVersion }
        }
    }
    Else { $Result = 'Not Found' }
    Write-Output "$Result|$($InstalledApplication.Name.Trim())|$($InstalledApplication.Version)|$Operator|$ReferenceVersion"