#Requires -Version 5.1
# Behavior tests for Modules/MsiTools. The module is imported (it only defines functions);
# Write-Host and every Windows Installer COM call are mocked, so these run on any OS.

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
        Mock Get-MsiInstallerObject -ModuleName MsiTools { [pscustomobject]@{ Kind = 'Installer' } }
        Mock Close-MsiComObject -ModuleName MsiTools
        Mock Invoke-MsiComMember -ModuleName MsiTools {
            switch ($Name) {
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
