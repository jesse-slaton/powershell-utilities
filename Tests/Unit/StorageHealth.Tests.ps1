#Requires -Version 5.1
# Behavior tests for Modules/StorageHealth. The module is imported (it only defines functions);
# every CIM call and native tool is mocked, so these run on any OS. Windows-only commands are
# stubbed with Register-CommandStub first so Mock can find them on macOS and Linux.

BeforeDiscovery {
    $script:onWindows = $env:OS -eq 'Windows_NT'
    $script:wow64PowerShell = if ($script:onWindows) { Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe' }
    # The shadow copy classes need administrator rights, so a non-elevated run skips the 32-bit tests.
    $script:isAdministrator = $script:onWindows -and ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $script:canRunWow64 = $script:isAdministrator -and [Environment]::Is64BitOperatingSystem -and (Test-Path -LiteralPath $script:wow64PowerShell)
}

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $PSScriptRoot '../TestHelpers.psm1') -Force
    Register-CommandStub -Name Get-CimInstance -Parameter ClassName, Namespace, Filter
    Register-CommandStub -Name Invoke-CimMethod -Parameter ClassName, Namespace, MethodName, Arguments
    Register-CommandStub -Name vssadmin
    Import-Module (Join-Path $repoRoot 'Modules/StorageHealth/StorageHealth.psd1') -Force
}

AfterAll {
    Remove-Module -Name StorageHealth -Force -ErrorAction SilentlyContinue
    Remove-CommandStub -Name Get-CimInstance, Invoke-CimMethod, vssadmin
}

Describe 'Get-LastShadowCopyDate' {
    It 'returns the newest InstallDate in the original format, with no colon in the offset' {
        $newest = Get-Date -Year 2026 -Month 11 -Day 5 -Hour 14 -Minute 30 -Second 0
        Mock Get-CimInstance -ModuleName StorageHealth -ParameterFilter { $ClassName -eq 'Win32_ShadowCopy' } {
            [pscustomobject]@{ InstallDate = $newest.AddDays(-3) }
            [pscustomobject]@{ InstallDate = $newest }
            [pscustomobject]@{ InstallDate = $newest.AddDays(-1) }
        }
        $expected = (Get-Date -Date $newest -Format 'ddd, dd MMM yyyy HH:mm zzz') -replace ':(\d{2})$', '$1'
        $result = Get-LastShadowCopyDate
        $result | Should -Be $expected
        $result | Should -Match '^\S+, 05 \S+ 2026 14:30 [+-]\d{4}$'
    }

    It 'returns nothing, without an error, when there are no shadow copies' {
        Mock Get-CimInstance -ModuleName StorageHealth { }
        $result = Get-LastShadowCopyDate -ErrorVariable err
        $result | Should -BeNullOrEmpty
        $err | Should -BeNullOrEmpty
    }

    It 'queries CIM in-process instead of through a loopback Invoke-Command' {
        Mock Get-CimInstance -ModuleName StorageHealth { }
        Mock Invoke-Command -ModuleName StorageHealth { throw 'Invoke-Command must not be used' }
        $null = Get-LastShadowCopyDate
        Should -Invoke Get-CimInstance -ModuleName StorageHealth -Times 1 -Exactly -ParameterFilter { $ClassName -eq 'Win32_ShadowCopy' }
        Should -Invoke Invoke-Command -ModuleName StorageHealth -Times 0 -Exactly
    }

    It 'lets a failed query surface as an error instead of an empty result' {
        # A non-terminating CIM error (as for access denied), raised under the caller's -ErrorAction.
        Mock Get-CimInstance -ModuleName StorageHealth { Write-Error 'Access denied' -ErrorAction $PesterBoundParameters['ErrorAction'] }
        { Get-LastShadowCopyDate } | Should -Throw '*Access denied*'
    }
}

Describe 'Test-ShadowCopy' {
    It 'returns <Expected> for <Count> shadow copies' -ForEach @(
        @{ Count = 0; Expected = $false }
        @{ Count = 1; Expected = $true }
        @{ Count = 3; Expected = $true }
    ) {
        $n = $Count
        Mock Get-CimInstance -ModuleName StorageHealth -ParameterFilter { $ClassName -eq 'Win32_ShadowCopy' } {
            for ($i = 0; $i -lt $n; $i++) { [pscustomobject]@{ ID = "{$i}" } }
        }
        $result = Test-ShadowCopy
        $result | Should -BeOfType [bool]
        $result | Should -Be $Expected
    }

    It 'returns $true for a single object that has no Count property' {
        # The 5.1 bug from the former script: one CIM result is a scalar, not an array.
        Mock Get-CimInstance -ModuleName StorageHealth { New-Object -TypeName psobject }
        Test-ShadowCopy | Should -BeTrue
    }

    It 'lets a failed query surface as an error instead of $false' {
        Mock Get-CimInstance -ModuleName StorageHealth { Write-Error 'Access denied' -ErrorAction $PesterBoundParameters['ErrorAction'] }
        { Test-ShadowCopy } | Should -Throw '*Access denied*'
    }

    It 'does not use Invoke-Command' {
        Mock Get-CimInstance -ModuleName StorageHealth { }
        Mock Invoke-Command -ModuleName StorageHealth { throw 'Invoke-Command must not be used' }
        Test-ShadowCopy | Should -BeFalse
        Should -Invoke Invoke-Command -ModuleName StorageHealth -Times 0 -Exactly
    }
}

Describe 'Get-ShadowCimInstance (private)' {
    It 'queries with Get-CimInstance when the process matches the operating system bitness' {
        Mock Test-Wow64Process -ModuleName StorageHealth { $false }
        Mock Invoke-Wow64CimQuery -ModuleName StorageHealth { throw 'must not be used' }
        Mock Get-CimInstance -ModuleName StorageHealth { [pscustomobject]@{ ID = 1 } }
        $result = @(InModuleScope StorageHealth { Get-ShadowCimInstance -ClassName Win32_ShadowCopy })
        $result.Count | Should -Be 1
        Should -Invoke Get-CimInstance -ModuleName StorageHealth -Times 1 -Exactly -ParameterFilter { $ClassName -eq 'Win32_ShadowCopy' }
    }

    It 'asks for the 64-bit provider from 32-bit PowerShell on 64-bit Windows' {
        # The VSS WMI provider answers "Initialization failure" to a 32-bit caller otherwise.
        Mock Test-Wow64Process -ModuleName StorageHealth { $true }
        Mock Get-CimInstance -ModuleName StorageHealth { throw 'must not be used' }
        Mock Invoke-Wow64CimQuery -ModuleName StorageHealth { [pscustomobject]@{ ID = 1 }; [pscustomobject]@{ ID = 2 } }
        $result = @(InModuleScope StorageHealth { Get-ShadowCimInstance -ClassName Win32_ShadowStorage })
        $result.Count | Should -Be 2
        Should -Invoke Invoke-Wow64CimQuery -ModuleName StorageHealth -Times 1 -Exactly -ParameterFilter { $ClassName -eq 'Win32_ShadowStorage' }
    }

    It 'only accepts the two shadow copy classes' {
        { InModuleScope StorageHealth { Get-ShadowCimInstance -ClassName Win32_LogicalDisk } } | Should -Throw
    }
}

Describe 'StorageHealth from 32-bit Windows PowerShell' {
    It 'answers Test-ShadowCopy and Get-LastShadowCopyDate without an error' -Skip:(-not $script:canRunWow64) {
        # Runs the real module in a 32-bit powershell.exe on 64-bit Windows (a WOW64 process),
        # where a plain Get-CimInstance of Win32_ShadowCopy fails with "Initialization failure".
        $manifest = Join-Path $repoRoot 'Modules/StorageHealth/StorageHealth.psd1'
        $wow64 = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
        $command = "`$ErrorActionPreference = 'Stop'; Import-Module '$manifest'; " +
            "if ([Environment]::Is64BitProcess) { throw 'not a 32-bit process' }; " +
            "'has=' + (Test-ShadowCopy); 'last=' + (Get-LastShadowCopyDate)"
        $output = @(& $wow64 -NoProfile -NonInteractive -Command $command 2>&1)
        $LASTEXITCODE | Should -Be 0 -Because ($output -join ' ')
        $output[0] | Should -Match '^has=(True|False)$'
    }

    It 'answers Get-ShadowStorageMaxSize without an Initialization failure' -Skip:(-not $script:canRunWow64) {
        # Win32_ShadowStorage.Volume is a reference property; this reads it through the 64-bit
        # provider path. A computer with no shadow storage association throws that error instead.
        $manifest = Join-Path $repoRoot 'Modules/StorageHealth/StorageHealth.psd1'
        $wow64 = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
        $command = "Import-Module '$manifest' -ErrorAction Stop; " +
            "if ([Environment]::Is64BitProcess) { throw 'not a 32-bit process' }; " +
            "try { `$m = Get-ShadowStorageMaxSize; 'max=ok ' + `$m.MaxSpaceGB } catch { 'max=' + `$_.Exception.Message }"
        $output = @(& $wow64 -NoProfile -NonInteractive -Command $command 2>&1)
        $LASTEXITCODE | Should -Be 0 -Because ($output -join ' ')
        $output[0] | Should -Match '^max=(ok \d|Could not determine the shadow storage maximum size: no shadow storage association)'
    }
}

Describe 'Enable-SystemDriveRestore from 32-bit PowerShell' {
    It 'throws before changing anything' {
        $savedSystemDrive = $env:SystemDrive
        try {
            $env:SystemDrive = 'C:'
            Mock Test-Wow64Process -ModuleName StorageHealth { $true }
            Mock Invoke-CimMethod -ModuleName StorageHealth { throw 'must not be called' }
            Mock Invoke-VssAdmin -ModuleName StorageHealth { throw 'must not be called' }
            { Enable-SystemDriveRestore -Confirm:$false } | Should -Throw '*must run in 64-bit PowerShell*'
            Should -Invoke Invoke-CimMethod -ModuleName StorageHealth -Times 0 -Exactly
            Should -Invoke Invoke-VssAdmin -ModuleName StorageHealth -Times 0 -Exactly
        }
        finally {
            $env:SystemDrive = $savedSystemDrive
        }
    }
}

Describe 'Enable-SystemDriveRestore' {
    BeforeAll {
        $savedSystemDrive = $env:SystemDrive
    }

    BeforeEach {
        $env:SystemDrive = 'C:'
        Mock Invoke-CimMethod -ModuleName StorageHealth { [pscustomobject]@{ ReturnValue = 0 } }
        Mock Invoke-VssAdmin -ModuleName StorageHealth { 'Successfully resized the shadow copy storage association' }
    }

    AfterAll {
        $env:SystemDrive = $savedSystemDrive
    }

    It 'enables System Restore through the SystemRestore CIM class, not Enable-ComputerRestore' {
        $result = Enable-SystemDriveRestore -Confirm:$false
        Should -Invoke Invoke-CimMethod -ModuleName StorageHealth -Times 1 -Exactly -ParameterFilter {
            $Namespace -eq 'root/default' -and $ClassName -eq 'SystemRestore' -and $MethodName -eq 'Enable' -and
            $Arguments.Drive -eq 'C:\' -and $Arguments.WaitTillEnabled -eq $true
        }
        $result | Should -Be 'Successfully resized the shadow copy storage association'
    }

    It 'caps the system drive shadow storage at 10 percent' {
        $null = Enable-SystemDriveRestore -Confirm:$false
        Should -Invoke Invoke-VssAdmin -ModuleName StorageHealth -Times 1 -Exactly -ParameterFilter {
            ($ArgumentList -join ' ') -eq 'resize ShadowStorage /For=C: /On=C: /MaxSize=10%'
        }
    }

    It 'accepts a SystemDrive value that already ends in a backslash' {
        $env:SystemDrive = 'D:\'
        $null = Enable-SystemDriveRestore -Confirm:$false
        Should -Invoke Invoke-CimMethod -ModuleName StorageHealth -Times 1 -Exactly -ParameterFilter { $Arguments.Drive -eq 'D:\' }
        Should -Invoke Invoke-VssAdmin -ModuleName StorageHealth -Times 1 -Exactly -ParameterFilter { $ArgumentList -contains '/For=D:' }
    }

    It 'throws on a non-zero SystemRestore.Enable return value and does not resize' {
        Mock Invoke-CimMethod -ModuleName StorageHealth { [pscustomobject]@{ ReturnValue = 1058 } }
        { Enable-SystemDriveRestore -Confirm:$false } | Should -Throw '*return value 1058*'
        Should -Invoke Invoke-VssAdmin -ModuleName StorageHealth -Times 0 -Exactly
    }

    It 'changes nothing with -WhatIf' {
        Enable-SystemDriveRestore -WhatIf
        Should -Invoke Invoke-CimMethod -ModuleName StorageHealth -Times 0 -Exactly
        Should -Invoke Invoke-VssAdmin -ModuleName StorageHealth -Times 0 -Exactly
    }

    It 'throws when SystemDrive is not set' {
        $env:SystemDrive = $null
        { Enable-SystemDriveRestore -Confirm:$false } | Should -Throw '*SystemDrive*'
        Should -Invoke Invoke-CimMethod -ModuleName StorageHealth -Times 0 -Exactly
    }
}

Describe 'Enable-SystemDriveRestore with a failing vssadmin' {
    # No Invoke-VssAdmin mock here: the real helper runs, so the -ErrorAction Stop at the call
    # site is what turns a vssadmin failure into a terminating error.
    BeforeAll {
        $savedSystemDrive = $env:SystemDrive
    }

    BeforeEach {
        $env:SystemDrive = 'C:'
        Mock Invoke-CimMethod -ModuleName StorageHealth { [pscustomobject]@{ ReturnValue = 0 } }
    }

    AfterAll {
        $env:SystemDrive = $savedSystemDrive
    }

    It 'throws when vssadmin exits non-zero' {
        Mock vssadmin -ModuleName StorageHealth { $global:LASTEXITCODE = 2; 'Error: Access is denied.' }
        { Enable-SystemDriveRestore -Confirm:$false } | Should -Throw '*vssadmin.exe resize ShadowStorage /For=C: /On=C: /MaxSize=10% failed with exit code 2*'
    }

    It 'throws when vssadmin prints an error but exits with 0' {
        Mock vssadmin -ModuleName StorageHealth { $global:LASTEXITCODE = 0; 'Error: The specified volume is not supported.' }
        { Enable-SystemDriveRestore -Confirm:$false } | Should -Throw '*The specified volume is not supported*'
    }
}

Describe 'Invoke-VssAdmin (private)' {
    It 'passes each argument to vssadmin.exe and returns its output' {
        Mock vssadmin -ModuleName StorageHealth { $global:LASTEXITCODE = 0; 'line 1'; 'line 2' }
        $result = InModuleScope StorageHealth { Invoke-VssAdmin -ArgumentList 'list', 'shadowstorage' }
        $result | Should -Be @('line 1', 'line 2')
        Should -Invoke vssadmin -ModuleName StorageHealth -Times 1 -Exactly -ParameterFilter {
            # A stub on macOS and Linux collects the arguments in StubRemainingArguments; the real
            # vssadmin.exe on Windows gets them in $args.
            ((@($args) + @($StubRemainingArguments) | Where-Object { $_ }) -join " ") -eq "list shadowstorage"
        }
    }

    It 'writes an error with the exit code and output on failure' {
        Mock vssadmin -ModuleName StorageHealth { $global:LASTEXITCODE = 2; 'Error: Access is denied.' }
        $result = InModuleScope StorageHealth { Invoke-VssAdmin -ArgumentList 'resize', 'ShadowStorage' -ErrorVariable err -ErrorAction SilentlyContinue; $err }
        "$result" | Should -Match 'vssadmin\.exe resize ShadowStorage failed with exit code 2: Error: Access is denied\.'
    }

    It 'writes an error when vssadmin reports an error but exits with 0' {
        # vssadmin exit codes are undocumented; an "Error:" line is the reliable failure signal.
        Mock vssadmin -ModuleName StorageHealth { $global:LASTEXITCODE = 0; 'vssadmin 1.1 - Volume Shadow Copy Service administrative command-line tool'; 'Error: The specified volume is not supported.' }
        $result = InModuleScope StorageHealth { Invoke-VssAdmin -ArgumentList 'resize', 'ShadowStorage' -ErrorVariable err -ErrorAction SilentlyContinue; $err }
        "$result" | Should -Match 'vssadmin\.exe resize ShadowStorage failed with exit code 0: .*Error: The specified volume is not supported\.'
    }
}

Describe 'Get-ShadowStorageMaxSize' {
    BeforeAll {
        $savedSystemDrive = $env:SystemDrive
        $volumeId = '\\?\Volume{0c4d8f2e-1111-2222-3333-444455556666}\'
        $otherId = '\\?\Volume{9f9f9f9f-aaaa-bbbb-cccc-ddddeeeeffff}\'
    }

    BeforeEach {
        $env:SystemDrive = 'C:'
        Mock Get-CimInstance -ModuleName StorageHealth -ParameterFilter { $ClassName -eq 'Win32_Volume' } {
            [pscustomobject]@{ DeviceID = $volumeId; Capacity = 500GB }
        }
        Mock Get-CimInstance -ModuleName StorageHealth -ParameterFilter { $ClassName -eq 'Win32_ShadowStorage' } {
            [pscustomobject]@{ Volume = [pscustomobject]@{ DeviceID = $otherId }; MaxSpace = 1GB }
            [pscustomobject]@{ Volume = [pscustomobject]@{ DeviceID = $volumeId }; MaxSpace = 50GB }
        }
    }

    AfterAll {
        $env:SystemDrive = $savedSystemDrive
    }

    It 'returns the system drive association as a percentage of capacity and in GB' {
        $result = Get-ShadowStorageMaxSize
        $result.Drive | Should -Be 'C:'
        $result.MaxSpacePercent | Should -Be 10
        $result.MaxSpaceGB | Should -Be 50
        Should -Invoke Get-CimInstance -ModuleName StorageHealth -Times 1 -Exactly -ParameterFilter {
            $ClassName -eq 'Win32_Volume' -and $Filter -eq "DriveLetter='C:'"
        }
    }

    It 'rounds both values to two decimals' {
        Mock Get-CimInstance -ModuleName StorageHealth -ParameterFilter { $ClassName -eq 'Win32_Volume' } {
            [pscustomobject]@{ DeviceID = $volumeId; Capacity = 300GB }
        }
        Mock Get-CimInstance -ModuleName StorageHealth -ParameterFilter { $ClassName -eq 'Win32_ShadowStorage' } {
            [pscustomobject]@{ Volume = [pscustomobject]@{ DeviceID = $volumeId }; MaxSpace = 20GB + 123456789 }
        }
        $result = Get-ShadowStorageMaxSize
        $result.MaxSpacePercent | Should -Be 6.7
        $result.MaxSpaceGB | Should -Be 20.11
    }

    It 'throws when the system drive has no shadow storage association' {
        Mock Get-CimInstance -ModuleName StorageHealth -ParameterFilter { $ClassName -eq 'Win32_ShadowStorage' } {
            [pscustomobject]@{ Volume = [pscustomobject]@{ DeviceID = $otherId }; MaxSpace = 1GB }
        }
        { Get-ShadowStorageMaxSize } | Should -Throw '*no shadow storage association for C:*'
    }

    It 'throws when no volume matches the system drive' {
        Mock Get-CimInstance -ModuleName StorageHealth -ParameterFilter { $ClassName -eq 'Win32_Volume' } { }
        { Get-ShadowStorageMaxSize } | Should -Throw '*no volume found for C:*'
    }

    It 'reads the shadow storage through the 64-bit provider from 32-bit PowerShell on 64-bit Windows' {
        # A plain Win32_ShadowStorage query fails there with "Initialization failure".
        Mock Test-Wow64Process -ModuleName StorageHealth { $true }
        Mock Invoke-Wow64CimQuery -ModuleName StorageHealth -ParameterFilter { $ClassName -eq 'Win32_ShadowStorage' } {
            [pscustomobject]@{ Volume = [pscustomobject]@{ DeviceID = $volumeId }; MaxSpace = 50GB }
        }
        (Get-ShadowStorageMaxSize).MaxSpaceGB | Should -Be 50
        Should -Invoke Invoke-Wow64CimQuery -ModuleName StorageHealth -Times 1 -Exactly
        Should -Invoke Get-CimInstance -ModuleName StorageHealth -Times 0 -Exactly -ParameterFilter { $ClassName -eq 'Win32_ShadowStorage' }
    }
}
