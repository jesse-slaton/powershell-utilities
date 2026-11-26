#Requires -Version 5.1
# Behavior tests for Modules/MsiTools. The module is imported (it only defines functions);
# Write-Host and every Windows Installer COM call are mocked, so these run on any OS. The last
# Describe block uses the real WindowsInstaller.Installer COM object and runs on Windows only.

BeforeDiscovery {
    # $IsWindows does not exist on Windows PowerShell 5.1; $env:OS is Windows_NT on every Windows.
    $script:onWindows = $env:OS -eq 'Windows_NT'
}

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'Modules/MsiTools/MsiTools.psd1') -Force
}

AfterAll {
    Remove-Module -Name MsiTools -Force -ErrorAction SilentlyContinue
}

Describe 'Format-MsiLog' {
    BeforeAll {
        $fixture = Join-Path $TestDrive 'install.log'
        $lines = @(
            'Verbose loading package'
            'Debug value=1'
            'Info install started'
            'Warning disk space low'
            'Error 1603 fatal error during installation'
            'MSI (s) (A4:B8) [10:00:00:000]: Product: Example -- Installation failed.'
            'Notice unknown level word'
        )
        Set-Content -Path $fixture -Value $lines
    }

    BeforeEach {
        Mock Write-Host -ModuleName MsiTools
    }

    It 'writes <Line> in <Color>' -ForEach @(
        @{ Line = 'Verbose loading package'; Color = 'Gray' }
        @{ Line = 'Debug value=1'; Color = 'DarkGray' }
        @{ Line = 'Info install started'; Color = 'White' }
        @{ Line = 'Warning disk space low'; Color = 'Yellow' }
        @{ Line = 'Error 1603 fatal error during installation'; Color = 'Red' }
    ) {
        Get-Content -Path $fixture | Format-MsiLog
        Should -Invoke Write-Host -ModuleName MsiTools -Times 1 -Exactly -ParameterFilter {
            $Object -eq $Line -and $ForegroundColor -eq $Color
        }
    }

    It 'writes lines without a known level word in the default color' {
        Get-Content -Path $fixture | Format-MsiLog
        foreach ($plain in 'MSI (s) (A4:B8) [10:00:00:000]: Product: Example -- Installation failed.', 'Notice unknown level word') {
            Should -Invoke Write-Host -ModuleName MsiTools -Times 1 -Exactly -ParameterFilter {
                $Object -eq $plain -and -not $PesterBoundParameters.ContainsKey('ForegroundColor')
            }
        }
        Should -Invoke Write-Host -ModuleName MsiTools -Times 7 -Exactly
    }

    It 'splits one CRLF string into lines and outputs nothing to the pipeline' {
        $output = ($lines -join "`r`n") | Format-MsiLog
        $output | Should -BeNullOrEmpty
        Should -Invoke Write-Host -ModuleName MsiTools -Times 1 -Exactly -ParameterFilter {
            $Object -eq 'Error 1603 fatal error during installation' -and $ForegroundColor -eq 'Red'
        }
    }

    It 'still answers to the Colorize-MsiLog alias' {
        Colorize-MsiLog -Log 'Error boom'
        Should -Invoke Write-Host -ModuleName MsiTools -Times 1 -Exactly -ParameterFilter { $ForegroundColor -eq 'Red' }
    }
}

Describe 'Get-MsiFileInfo' {
    BeforeAll {
        $msi = Join-Path $TestDrive 'app.msi'
        $mst = Join-Path $TestDrive 'custom.mst'
        Set-Content -Path $msi -Value 'not a real msi'
        Set-Content -Path $mst -Value 'not a real mst'
    }

    BeforeEach {
        # Fake COM objects: each view yields one record per row below, then $null. A view
        # opened after ApplyTransform also yields an AppliedTransforms row listing them in order.
        # $script:comCalls records each View.Close and each release in call order.
        $script:comCalls = [System.Collections.ArrayList]::new()
        Mock Get-MsiInstallerObject -ModuleName MsiTools { [pscustomobject]@{ Kind = 'Installer' } }
        Mock Close-MsiComObject -ModuleName MsiTools {
            $kind = if ($null -eq $InputObject) { 'null' } else { $InputObject.Kind }
            $null = $script:comCalls.Add("Release:$kind")
        }
        Mock Invoke-MsiComMember -ModuleName MsiTools {
            switch ($Name) {
                'Close' { $null = $script:comCalls.Add("Close:$($Target.Kind)") }
                'OpenDatabase' { [pscustomobject]@{ Kind = 'Database'; Path = $Arguments[0]; Applied = [System.Collections.ArrayList]::new() } }
                'ApplyTransform' { $null = $Target.Applied.Add($Arguments[0]) }
                'OpenView' {
                    $rows = @(@('ProductName', 'Example App'), @('ProductVersion', '1.2.3'),
                        @('ALLUSERS', '1'), @('SecureCustomProperties', 'FOO;BAR'))
                    if ($Target.Applied.Count -gt 0) { $rows += , @('AppliedTransforms', ($Target.Applied -join ';')) }
                    [pscustomobject]@{ Kind = 'View'; Query = $Arguments[0]; Queue = [System.Collections.Queue]::new($rows) }
                }
                'Fetch' { if ($Target.Queue.Count -gt 0) { [pscustomobject]@{ Kind = 'Record'; Fields = $Target.Queue.Dequeue() } } }
                'StringData' { $Target.Fields[$Arguments[0] - 1] }
                default { $null }
            }
        }
    }

    It 'returns every property from the Property table, closes the view and releases the COM objects' {
        $result = Get-MsiFileInfo -FilePath $msi
        $result | Should -BeOfType [hashtable]
        $result.Count | Should -Be 4
        $result['ProductName'] | Should -Be 'Example App'
        $result['ProductVersion'] | Should -Be '1.2.3'
        Should -Invoke Invoke-MsiComMember -ModuleName MsiTools -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'OpenDatabase' -and $Arguments[0] -eq (Get-Item $msi).FullName -and $Arguments[1] -eq 0
        }
        Should -Invoke Invoke-MsiComMember -ModuleName MsiTools -Times 1 -Exactly -ParameterFilter { $Name -eq 'OpenView' -and $Arguments[0] -match 'FROM Property' }
        Should -Invoke Invoke-MsiComMember -ModuleName MsiTools -Times 1 -Exactly -ParameterFilter { $Name -eq 'Close' }
        foreach ($kind in 'Installer', 'Database', 'View') {
            Should -Invoke Close-MsiComObject -ModuleName MsiTools -Times 1 -Exactly -ParameterFilter { $InputObject.Kind -eq $kind }
        }
        Should -Invoke Close-MsiComObject -ModuleName MsiTools -Times 4 -Exactly -ParameterFilter { $InputObject.Kind -eq 'Record' }
    }

    It 'closes the view before releasing the view, then the database, then the installer' {
        $null = Get-MsiFileInfo -FilePath $msi
        # Each fetched record is released in the loop, so the Record slot is empty by the finally block.
        $script:comCalls -join ',' | Should -Be ((@('Release:Record') * 4) + 'Close:View', 'Release:null', 'Release:View', 'Release:Database', 'Release:Installer' -join ',')
    }

    It 'releases a record left over by a failed read before the view and the database' {
        Mock Invoke-MsiComMember -ModuleName MsiTools -ParameterFilter { $Name -eq 'StringData' } { throw 'Read failed' }
        $null = Get-MsiFileInfo -FilePath $msi -ErrorVariable err -ErrorAction SilentlyContinue
        "$err" | Should -Match 'app\.msi: Read failed'
        $script:comCalls -join ',' | Should -Be 'Close:View,Release:Record,Release:View,Release:Database,Release:Installer'
    }

    It 'still releases the record, view and database when View.Close fails, and reports the failure' {
        Mock Invoke-MsiComMember -ModuleName MsiTools -ParameterFilter { $Name -eq 'Close' } {
            $null = $script:comCalls.Add('Close:View')
            throw 'Close failed'
        }
        # A subfolder keeps this extra .msi out of the pipeline test's Get-ChildItem of $TestDrive.
        $folder = New-Item -ItemType Directory -Path (Join-Path $TestDrive 'close-fails') -Force
        $second = Join-Path $folder.FullName 'second-close.msi'
        Set-Content -Path $second -Value 'not a real msi'
        $out = @($msi, $second | Get-MsiFileInfo -ErrorAction Continue 2>&1)
        $err = @($out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
        @(($out.Count - $err.Count), $err.Count) | Should -Be @(2, 2)
        "$($err[0])" | Should -Match 'Failed to close the MSI view for .*app\.msi: Close failed'
        "$($err[1])" | Should -Match 'Failed to close the MSI view for .*second-close\.msi: Close failed'
        $perFile = 'Close:View,Release:null,Release:View,Release:Database'
        ($script:comCalls | Where-Object { $_ -ne 'Release:Record' }) -join ',' | Should -Be "$perFile,$perFile,Release:Installer"
    }

    It 'releases the installer when -ErrorAction Stop ends the run on a View.Close failure' {
        Mock Invoke-MsiComMember -ModuleName MsiTools -ParameterFilter { $Name -eq 'Close' } {
            $null = $script:comCalls.Add('Close:View')
            throw 'Close failed'
        }
        { Get-MsiFileInfo -FilePath $msi -ErrorAction Stop } | Should -Throw '*Failed to close the MSI view*'
        @($script:comCalls | Where-Object { $_ -eq 'Release:Installer' }).Count | Should -Be 1
        $script:comCalls[-1] | Should -Be 'Release:Installer'
    }

    It 'releases the installer when -ErrorAction Stop ends the run on a read failure' {
        Mock Invoke-MsiComMember -ModuleName MsiTools -ParameterFilter { $Name -eq 'OpenView' } { throw 'Open view failed' }
        { Get-MsiFileInfo -FilePath $msi -ErrorAction Stop } | Should -Throw '*Failed to get MSI file properties*'
        @($script:comCalls | Where-Object { $_ -eq 'Release:Installer' }).Count | Should -Be 1
        $script:comCalls[-1] | Should -Be 'Release:Installer'
    }

    It 'returns only upper-case names for -PropertyType Public' {
        $result = Get-MsiFileInfo -FilePath $msi -PropertyType Public
        @($result.Keys) | Should -Be @('ALLUSERS')
    }

    It 'returns only mixed-case names for -PropertyType Private' {
        $result = Get-MsiFileInfo -FilePath $msi -PropertyType Private
        @($result.Keys | Sort-Object) -join ',' | Should -Be 'ProductName,ProductVersion,SecureCustomProperties'
    }

    It 'applies each transform in order with error conditions suppressed before reading' {
        $second = Join-Path $TestDrive 'second.mst'
        Set-Content -Path $second -Value 'not a real mst'
        $result = Get-MsiFileInfo -FilePath $msi -Transform $mst, $second
        $result['AppliedTransforms'] | Should -Be ('{0};{1}' -f (Get-Item $mst).FullName, (Get-Item $second).FullName)
        Should -Invoke Invoke-MsiComMember -ModuleName MsiTools -Times 2 -Exactly -ParameterFilter { $Name -eq 'ApplyTransform' -and $Arguments[1] -eq 63 }
    }

    It 'reports a missing transform as an error for that MSI and reads nothing' {
        $result = Get-MsiFileInfo -FilePath $msi -Transform (Join-Path $TestDrive 'missing.mst') -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$err" | Should -Match 'app\.msi: Transform file not found: .*missing\.mst'
        Should -Invoke Invoke-MsiComMember -ModuleName MsiTools -Times 0 -Exactly -ParameterFilter { $Name -eq 'OpenView' }
    }

    It 'keeps property names that differ only by case as separate keys' {
        Mock Invoke-MsiComMember -ModuleName MsiTools -ParameterFilter { $Name -eq 'OpenView' } {
            $rows = @(@('Foo', 'a'), @('FOO', 'b'))
            [pscustomobject]@{ Kind = 'View'; Queue = [System.Collections.Queue]::new($rows) }
        }
        $result = Get-MsiFileInfo -FilePath $msi
        $result | Should -BeOfType [hashtable]
        @($result.Count, $result['Foo'], $result['FOO']) | Should -Be @(2, 'a', 'b')
    }

    It 'resolves relative -FilePath and -Transform against the current location' {
        Push-Location $TestDrive
        try { $null = Get-MsiFileInfo -FilePath 'app.msi' -Transform 'custom.mst' } finally { Pop-Location }
        Should -Invoke Invoke-MsiComMember -ModuleName MsiTools -Times 1 -Exactly -ParameterFilter { $Name -eq 'OpenDatabase' -and $Arguments[0] -eq (Get-Item $msi).FullName }
        Should -Invoke Invoke-MsiComMember -ModuleName MsiTools -Times 1 -Exactly -ParameterFilter { $Name -eq 'ApplyTransform' -and $Arguments[0] -eq (Get-Item $mst).FullName }
    }

    It 'accepts MSI files from the pipeline and returns one result per file' {
        $second = Join-Path $TestDrive 'second.msi'
        Set-Content -Path $second -Value 'not a real msi'
        $results = @(Get-ChildItem -Path $TestDrive -Filter '*.msi' | Get-MsiFileInfo)
        $results.Count | Should -Be 2
        Should -Invoke Get-MsiInstallerObject -ModuleName MsiTools -Times 1 -Exactly
    }

    It 'writes a non-terminating error for a missing file and opens nothing' {
        $missing = Join-Path $TestDrive 'missing.msi'
        $result = Get-MsiFileInfo -FilePath $missing -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$err" | Should -Match 'MSI file not found'
        Should -Invoke Invoke-MsiComMember -ModuleName MsiTools -Times 0 -Exactly -ParameterFilter { $Name -eq 'OpenDatabase' }
    }

    It 'reports a bad drive or provider path as that input''s error without reusing the previous file' {
        $out = @($msi, 'NoSuchDrive:\x.msi', 'Env:\PATH' | Get-MsiFileInfo -ErrorAction Continue 2>&1)
        $err = @($out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
        @(($out.Count - $err.Count), $err.Count) | Should -Be @(1, 2)
        "$($err[0])" | Should -Match 'for NoSuchDrive:\\x\.msi: '
        "$($err[1])" | Should -Match 'for Env:\\PATH: Not a file system path'
        Should -Invoke Invoke-MsiComMember -ModuleName MsiTools -Times 1 -Exactly -ParameterFilter { $Name -eq 'OpenDatabase' }
        Get-MsiFileInfo -FilePath $msi -Transform $mst, 'NoSuchDrive:\x.mst' -ErrorVariable err -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        "$err" | Should -Match 'app\.msi: .*NoSuchDrive'
    }

    It 'rejects a non-file-system transform with one error naming the MSI and the transform' {
        # A file named PATH in the current directory is what Env:\PATH would wrongly resolve to.
        Set-Content -Path (Join-Path $TestDrive 'PATH') -Value 'not a real mst'
        Push-Location $TestDrive
        try { $out = @(Get-MsiFileInfo -FilePath $msi -Transform 'Env:\PATH' -ErrorAction Continue 2>&1) } finally { Pop-Location }
        $out.Count | Should -Be 1
        $out[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
        "$($out[0])" | Should -Match 'app\.msi: Transform Env:\\PATH is not a file system path'
        Should -Invoke Invoke-MsiComMember -ModuleName MsiTools -Times 0 -Exactly -ParameterFilter { $Name -eq 'ApplyTransform' }
    }

    It 'reports a COM failure as a non-terminating error that names the file' {
        Mock Invoke-MsiComMember -ModuleName MsiTools -ParameterFilter { $Name -eq 'OpenDatabase' } { throw 'Open database failed' }
        $result = Get-MsiFileInfo -FilePath $msi -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$err" | Should -Match 'app\.msi: .*Open database failed'
    }

    It 'still answers to the Get-MSIProperties alias' {
        (Get-MSIProperties -FilePath $msi)['ProductName'] | Should -Be 'Example App'
    }
}

Describe 'Invoke-MsiComMember' {
    BeforeAll {
        # Stand-in target: reports the .NET type each argument arrives as through InvokeMember.
        if (-not ('MsiArgumentProbe' -as [type])) {
            Add-Type -TypeDefinition 'public class MsiArgumentProbe { public string Kinds(object a, object b) { return a.GetType().FullName + "," + b.GetType().FullName; } }'
        }
    }

    It 'passes cmdlet output to the member as the plain value, not its PSObject wrapper' {
        $path = Join-Path $TestDrive 'held.msi'
        $kinds = & (Get-Module -Name MsiTools) {
            param($p)
            Invoke-MsiComMember -Target ([MsiArgumentProbe]::new()) -Name Kinds -Arguments @($p, 0)
        } $path
        $kinds | Should -Be 'System.String,System.Int32'
    }
}

Describe 'Close-MsiComObject' {
    # Not mocked: only the guard runs, because no input here is a COM object.
    It 'ignores $null' {
        $out = InModuleScope MsiTools { Close-MsiComObject -InputObject $null -ErrorVariable err -ErrorAction SilentlyContinue; @($err).Count }
        $out | Should -Be 0
    }

    It 'reports a value that is not a COM object instead of passing it to ReleaseComObject' {
        $out = InModuleScope MsiTools {
            Close-MsiComObject -InputObject ([pscustomobject]@{ Kind = 'Fake' }) -ErrorVariable err -ErrorAction SilentlyContinue
            Close-MsiComObject -InputObject 'not com' -ErrorVariable +err -ErrorAction SilentlyContinue
            $err
        }
        @($out).Count | Should -Be 2
        "$($out[0])" | Should -Match 'Not a COM object, so not released: System\.Management\.Automation\.PSCustomObject'
        "$($out[1])" | Should -Match 'Not a COM object, so not released: System\.String'
    }
}

Describe 'Get-MsiFileInfo against the real Windows Installer COM object' -Skip:(-not $script:onWindows) {
    BeforeAll {
        # Call through the module's own helper, so test and module share one invoke rule
        # (late binding, and PSObject wrappers removed before the arguments reach COM).
        function Invoke-RealMsiMember {
            param([object]$Target, [string]$Name, [object[]]$Arguments)
            & (Get-Module -Name MsiTools) { param($t, $n, $a) Invoke-MsiComMember -Target $t -Name $n -Arguments $a } $Target $Name $Arguments
        }

        # Release through the module's own helper, so test and module share one release rule:
        # $null is skipped and a non-COM value is reported, not passed to ReleaseComObject (whose
        # exception, thrown in a finally block, would hide the error that really went wrong).
        function Close-RealMsiObject {
            param([object]$InputObject)
            & (Get-Module -Name MsiTools) { param($o) Close-MsiComObject -InputObject $o } $InputObject
        }

        # Build a minimal MSI: just a Property table with three rows.
        function New-TestMsi {
            param([string]$Path)
            $installer = New-Object -ComObject WindowsInstaller.Installer
            $database = $null
            try {
                $database = Invoke-RealMsiMember $installer OpenDatabase @($Path, 3 <#msiOpenDatabaseModeCreate#>)
                foreach ($sql in @(
                        'CREATE TABLE `Property` (`Property` CHAR(72) NOT NULL, `Value` LONGCHAR NOT NULL PRIMARY KEY `Property`)'
                        'INSERT INTO `Property` (`Property`, `Value`) VALUES (''ProductName'', ''Pester Real COM'')'
                        'INSERT INTO `Property` (`Property`, `Value`) VALUES (''ProductVersion'', ''1.0.0'')'
                        'INSERT INTO `Property` (`Property`, `Value`) VALUES (''ALLUSERS'', ''1'')'
                    )) {
                    $view = Invoke-RealMsiMember $database OpenView @($sql)
                    try {
                        $null = Invoke-RealMsiMember $view Execute
                        $null = Invoke-RealMsiMember $view Close
                    } finally {
                        Close-RealMsiObject $view
                    }
                }
                $null = Invoke-RealMsiMember $database Commit
            } finally {
                Close-RealMsiObject $database
                Close-RealMsiObject $installer
            }
        }
    }

    It 'reads the Property table of a real MSI and releases it, so the file can be deleted' {
        $msi = Join-Path $TestDrive 'real.msi'
        New-TestMsi -Path $msi
        $result = Get-MsiFileInfo -FilePath $msi -ErrorAction Stop
        $result.Count | Should -Be 3
        $result['ProductName'] | Should -Be 'Pester Real COM'
        $result['ProductVersion'] | Should -Be '1.0.0'
        @((Get-MsiFileInfo -FilePath $msi -PropertyType Public -ErrorAction Stop).Keys) | Should -Be @('ALLUSERS')
        # No garbage collection here: the delete succeeds only if Get-MsiFileInfo released the database.
        Remove-Item -LiteralPath $msi -ErrorAction Stop
        Test-Path -LiteralPath $msi | Should -BeFalse
    }

    It 'cannot delete an MSI whose database is still open, so the delete above proves the release' {
        $msi = Join-Path $TestDrive 'held.msi'
        New-TestMsi -Path $msi
        $installer = New-Object -ComObject WindowsInstaller.Installer
        $database = $null
        try {
            $database = Invoke-RealMsiMember $installer OpenDatabase @($msi, 0 <#msiOpenDatabaseModeReadOnly#>)
            { Remove-Item -LiteralPath $msi -ErrorAction Stop } | Should -Throw
        } finally {
            Close-RealMsiObject $database
            Close-RealMsiObject $installer
        }
        Remove-Item -LiteralPath $msi -ErrorAction Stop
        Test-Path -LiteralPath $msi | Should -BeFalse
    }
}
