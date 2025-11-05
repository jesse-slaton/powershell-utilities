<#
.SYNOPSIS
    Extracts properties and metadata from MSI (Microsoft Installer) files.

.DESCRIPTION
    This function queries MSI installer files to extract properties such as product name,
    version, manufacturer, and other metadata. It uses the Windows Installer COM object
    to read the MSI database and can optionally apply MST (transform) files. Supports
    both public and private property types.

.PARAMETER FilePath
    The path to the MSI file(s) to query. Supports pipeline input and multiple files.
    Must be a valid path to an existing MSI file.

.PARAMETER Transform
    Optional path to an MST (transform) file to apply to the MSI database before
    querying properties. Transforms modify the MSI behavior or properties.

.PARAMETER PropertyType
    Specifies whether to query "Public" or "Private" properties from the MSI.
    Public properties are typically user-configurable, while private properties
    are internal to the installer.

.EXAMPLE
    Get-MSIProperties -FilePath "C:\Installers\app.msi"
    Extracts all properties from the specified MSI file.

.EXAMPLE
    Get-ChildItem "C:\Installers\*.msi" | Get-MSIProperties -PropertyType Public
    Queries public properties from all MSI files in the Installers directory.

.EXAMPLE
    Get-MSIProperties -FilePath "C:\app.msi" -Transform "C:\custom.mst"
    Extracts properties after applying a transform file to the MSI database.

.NOTES
    Author: System Administrator
    Purpose: MSI file analysis and metadata extraction
    Requires: Windows Installer COM object (WindowsInstaller.Installer)
    Dependencies: COM interop for MSI database access

.LINK
    about_Windows_Installer
#>
#Region Get-MSIProperties Function
function Get-MSIProperties {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True,
            ValueFromPipeline = $True,
            ValueFromPipelineByPropertyName = $True,
            HelpMessage = 'What is the path of the MSI you would like to query?')]
        [System.IO.FileInfo[]]$FilePath,
        [System.IO.FileInfo[]]$Transform,
        [ValidateSet("Public", "Private")]
        $PropertyType

    )
    begin {
        $WindowsInstaller = New-Object -com WindowsInstaller.Installer
    }

    process {
        Try {
            Test-Path -Path $FilePath -PathType Leaf -ErrorAction Stop | Out-Null
        }
        Catch {
            Write-Error -Message $_.Exception.Message ;
        }
      
        Try {
            $MSIDatabase = $WindowsInstaller.GetType().InvokeMember(
                "OpenDatabase",
                "InvokeMethod",
                $Null,
                $WindowsInstaller,
                @($FilePath.FullName, 0<#Read-Only#>)
            )
            If ($null -ne $Transform) {
                Try {
                    Test-Path -Path $Transform -PathType Leaf -ErrorAction Stop | Out-Null
                }
                Catch {
                    Write-Error -Message $_.Exception.Message ;
                }
                $MSIDatabase.ApplyTransform($Transform, 63)
                $MSIDatabase.GetType().InvokeMember(
                    "ApplyTransform"
                    , "InvokeMethod"
                    , $Null
                    , $MSIDatabase
                    , @($Transform.FullName, 63)
                )
                $MSIQuery = "SELECT * FROM _TransformView"
                $View = $MSIDatabase.GetType().InvokeMember(
                    "OpenView",
                    "InvokeMethod",
                    $Null,
                    $MSIDatabase,
                    ($MSIQuery)
                )
            }
            Else {
                $MSIQuery = "SELECT * FROM Property"
                $View = $MSIDatabase.GetType().InvokeMember(
                    "OpenView",
                    "InvokeMethod",
                    $Null,
                    $MSIDatabase,
                    ($MSIQuery)
                )
            }


            $View.GetType().InvokeMember("Execute", "InvokeMethod", $Null, $View, $Null)

            $Record = $View.GetType().InvokeMember(
                "Fetch",
                "InvokeMethod",
                $Null,
                $View,
                $Null
            )

            $MSIProperties = @{ }
            while ($null -ne $Record) {
                $MSIProperties[$Record.GetType().InvokeMember("StringData", "GetProperty", $Null, $Record, 1)] = $Record.GetType().InvokeMember("StringData", "GetProperty", $Null, $Record, 2)
                $Record = $View.GetType().InvokeMember(
                    "Fetch",
                    "InvokeMethod",
                    $Null,
                    $View,
                    $Null
                )
            }
            If ($null -ne $PropertyType) {
                Switch ($PropertyType) {
                    "Public" {
                        $RemoveProperties = @()
                        foreach ($Property in $MSIProperties.Keys) {
                            if ($Property -cne $Property.ToUpper()) {
                                $RemoveProperties += $Property
                            }
                        }
                        foreach ($r in $RemoveProperties) {
                            $MSIProperties.Remove($r)
                        }
                    }
                    "Private" {
                        $RemoveProperties = @()
                        foreach ($Property in $MSIProperties.Keys) {
                            if ($Property -ceq $Property.ToUpper()) {
                                $RemoveProperties += $Property
                            }
                        }
                        foreach ($r in $RemoveProperties) {
                            $MSIProperties.Remove($r)
                        }
                    }
                }
                $MSIProperties
            }
            Else {
                $MSIProperties
            }

        }
        catch {
            $Path | Select-Object *
            throw "Failed to get MSI file properties the error was: {0}." -f $_
        }
    }
    End {
        # Close MSI Database (otherwise a handle will be left open on the .MSI)
        $view.GetType().InvokeMember('Close', 'InvokeMethod', $null, $view, $null)
    } 
}

#endregion
