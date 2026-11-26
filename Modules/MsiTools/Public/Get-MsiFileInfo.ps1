function Get-MsiFileInfo {
    <#
    .SYNOPSIS
        Extracts properties and metadata from MSI (Microsoft Installer) files.

    .DESCRIPTION
        Reads the Property table of each MSI file through the Windows Installer COM object
        and returns one hashtable per file mapping property name to value (ProductName,
        ProductVersion, Manufacturer, ProductCode, and so on). Keys are case-sensitive, as
        MSI property names are: $result['ProductName'] works, $result['productname'] does not. The database is opened
        read-only; nothing is written to the MSI. Optional MST transform files are applied
        in memory before the table is read, so the result shows the transformed values.

        A missing file or transform, an unresolvable or non-file-system path, or a file that is
        not a readable MSI database writes a non-terminating error and the next file is processed.

        Formerly Get-MSIProperties in Scripts/FileSystem/Get-MSIFileInfo.ps1; that name is
        kept as an alias.

    .PARAMETER FilePath
        The path to the MSI file(s) to query. Supports pipeline input (for example from
        Get-ChildItem, which binds by FullName or PSPath) and multiple files. A relative
        path is resolved against the current PowerShell location. Wildcards are not expanded.

    .PARAMETER Transform
        Optional path(s) to MST transform files, applied in order to each MSI database
        before its properties are read. Each must be a file system path; a missing or
        non-file-system transform is reported as an error for that MSI.

    .PARAMETER PropertyType
        Public returns only public properties (names in all upper case, which users can
        set on the msiexec command line). Private returns only the others. Omit it to
        return every property.

    .EXAMPLE
        Get-MsiFileInfo -FilePath 'C:\Installers\app.msi'

        Returns every property of app.msi as a hashtable.

    .EXAMPLE
        Get-ChildItem 'C:\Installers\*.msi' | Get-MsiFileInfo -PropertyType Public

        Returns the public properties of every MSI in C:\Installers.

    .EXAMPLE
        (Get-MsiFileInfo -FilePath 'C:\app.msi' -Transform 'C:\custom.mst').ProductVersion

        Reads ProductVersion after applying custom.mst.

    .NOTES
        Windows only: requires the WindowsInstaller.Installer COM object. Part of the
        MsiTools module.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseLiteralInitializerForHashtable', '', Justification = 'Needs an ordinal comparer; @{} is case-insensitive.')]
    [CmdletBinding()]
    [Alias('Get-MSIProperties')]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory = $True,
            ValueFromPipeline = $True,
            ValueFromPipelineByPropertyName = $True,
            HelpMessage = 'What is the path of the MSI you would like to query?')]
        [Alias('FullName', 'PSPath')]
        [string[]]$FilePath,

        [string[]]$Transform,

        [ValidateSet("Public", "Private")]
        [string]$PropertyType
    )

    begin {
        $WindowsInstaller = Get-MsiInstallerObject
    }

    process {
        # A caller's -ErrorAction Stop turns each Write-Error below into a terminating error,
        # and PowerShell then skips the end block. Release the installer here on that path,
        # so its lifetime never depends on the garbage collector.
        try {
            foreach ($Path in $FilePath) {
                $MSIDatabase = $View = $Record = $Provider = $Drive = $null
                $File = $Path
                Try {
                    # Resolve inside Try against $PWD (.NET would use the process directory), so a
                    # bad path or drive is this input's error rather than a reuse of the previous $File.
                    $File = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path, [ref]$Provider, [ref]$Drive)
                    if ($Provider.Name -ne 'FileSystem') { $File = $Path; throw "Not a file system path ($($Provider.Name) provider)" }
                    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
                        Write-Error -Message "MSI file not found: $File" -Category ObjectNotFound -TargetObject $File
                        continue
                    }
                    $MSIDatabase = Invoke-MsiComMember -Target $WindowsInstaller -Name OpenDatabase -Arguments @($File, 0 <#Read-Only#>)

                    foreach ($MST in $Transform) {
                        $MSTProvider = $null
                        $MSTPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($MST, [ref]$MSTProvider, [ref]$Drive)
                        if ($MSTProvider.Name -ne 'FileSystem') { throw "Transform $MST is not a file system path ($($MSTProvider.Name) provider)" }
                        $MST = $MSTPath
                        if (-not (Test-Path -LiteralPath $MST -PathType Leaf)) {
                            throw "Transform file not found: $MST"
                        }
                        # 63 = suppress every transform error condition (msiTransformError*).
                        $null = Invoke-MsiComMember -Target $MSIDatabase -Name ApplyTransform -Arguments @($MST, 63)
                    }

                    $View = Invoke-MsiComMember -Target $MSIDatabase -Name OpenView -Arguments @('SELECT Property, Value FROM Property')
                    $null = Invoke-MsiComMember -Target $View -Name Execute

                    $MSIProperties = New-Object -TypeName System.Collections.Hashtable -ArgumentList ([System.StringComparer]::Ordinal)
                    $Record = Invoke-MsiComMember -Target $View -Name Fetch
                    while ($null -ne $Record) {
                        $Name = Invoke-MsiComMember -Target $Record -Name StringData -Kind GetProperty -Arguments @(1)
                        $MSIProperties[$Name] = Invoke-MsiComMember -Target $Record -Name StringData -Kind GetProperty -Arguments @(2)
                        Close-MsiComObject -InputObject $Record
                        $Record = $null
                        $Record = Invoke-MsiComMember -Target $View -Name Fetch
                    }

                    if ($PropertyType) {
                        $RemoveProperties = @(
                            foreach ($Property in $MSIProperties.Keys) {
                                $IsPublic = $Property -ceq $Property.ToUpper()
                                if (($PropertyType -eq 'Public') -ne $IsPublic) { $Property }
                            }
                        )
                        foreach ($r in $RemoveProperties) { $MSIProperties.Remove($r) }
                    }
                    $MSIProperties
                }
                Catch {
                    Write-Error -Message ("Failed to get MSI file properties for {0}: {1}" -f $File, $_.Exception.Message) -TargetObject $File
                }
                Finally {
                    # Close the view and release every COM object now, so the .msi file handle is
                    # freed here rather than whenever the garbage collector runs. A failed Close is
                    # reported, and the objects are still released (Record, View, then Database).
                    try {
                        if ($null -ne $View) {
                            $null = Invoke-MsiComMember -Target $View -Name Close
                        }
                    } catch {
                        Write-Error -Message ("Failed to close the MSI view for {0}: {1}" -f $File, $_.Exception.Message) -TargetObject $File
                    } finally {
                        foreach ($ComObject in $Record, $View, $MSIDatabase) { Close-MsiComObject -InputObject $ComObject }
                    }
                }
            }
        } catch {
            Close-MsiComObject -InputObject $WindowsInstaller
            $WindowsInstaller = $null
            throw
        }
    }

    end {
        Close-MsiComObject -InputObject $WindowsInstaller
    }
}
