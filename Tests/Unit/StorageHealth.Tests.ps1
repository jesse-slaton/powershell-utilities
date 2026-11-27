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
    Register-CommandStub -Name vssadmin, smartctl
    Register-CommandStub -Name Get-Disk -Parameter Number
    Register-CommandStub -Name Get-Partition -Parameter DriveLetter
    Import-Module (Join-Path $repoRoot 'Modules/StorageHealth/StorageHealth.psd1') -Force

    function New-SmartBuffer {
        # A 512-byte MSStorageDriver_FailurePredictData VendorSpecific buffer: 2 header bytes, then
        # one 12-byte record per attribute ID in $Values (ID, 2 flags, value, worst, 6 raw, reserved).
        param([System.Collections.IDictionary]$Values)
        $buffer = New-Object byte[] 512
        $offset = 2
        # GetEnumerator, not $Values[$id]: an int key on an ordered dictionary indexes by position.
        foreach ($entry in $Values.GetEnumerator()) {
            $buffer[$offset] = [byte]$entry.Key
            $buffer[$offset + 1] = 0x33
            $buffer[$offset + 3] = [byte]$entry.Value
            $buffer[$offset + 4] = [byte]$entry.Value
            $buffer[$offset + 5] = 7
            $offset += 12
        }
        , $buffer
    }
}

AfterAll {
    Remove-Module -Name StorageHealth -Force -ErrorAction SilentlyContinue
    Remove-CommandStub -Name Get-CimInstance, Invoke-CimMethod, vssadmin, smartctl, Get-Disk, Get-Partition
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

Describe 'ConvertFrom-SmartVendorSpecific (private)' {
    It 'returns one record per used slot, each with its own fields' {
        $buffer = New-SmartBuffer -Values ([ordered]@{ 5 = 100; 197 = 98 })
        $buffer[2 + 12 + 10] = 9
        $result = @(InModuleScope StorageHealth -Parameters @{ Buffer = $buffer } { param($Buffer) ConvertFrom-SmartVendorSpecific -VendorSpecific $Buffer })
        $result.Count | Should -Be 2
        @($result.AttrID) | Should -Be @(5, 197)
        @($result.AttrValue) | Should -Be @(100, 98)
        $result[0].StatusFlag1 | Should -Be 0x33
        $result[1].Raws | Should -Be @(7, 0, 0, 0, 0, 9)
    }

    It 'ignores bytes past the 30-entry attribute table' {
        $buffer = New-SmartBuffer -Values ([ordered]@{ 9 = 99 })
        $buffer[2 + 30 * 12] = 200
        $result = @(InModuleScope StorageHealth -Parameters @{ Buffer = $buffer } { param($Buffer) ConvertFrom-SmartVendorSpecific -VendorSpecific $Buffer })
        @($result.AttrID) | Should -Be @(9)
    }

    It 'returns nothing for an empty buffer' {
        InModuleScope StorageHealth { ConvertFrom-SmartVendorSpecific -VendorSpecific @() } | Should -BeNullOrEmpty
    }
}

Describe 'Get-SmartAttribute' {
    BeforeEach {
        Mock Test-IsAdministrator -ModuleName StorageHealth { $true }
        Mock Get-CimInstance -ModuleName StorageHealth -ParameterFilter { $ClassName -eq 'MSStorageDriver_FailurePredictData' } {
            [pscustomobject]@{ InstanceName = 'DISK_A_0'; VendorSpecific = (New-SmartBuffer -Values ([ordered]@{ 5 = 100; 194 = 40 })) }
            [pscustomobject]@{ InstanceName = 'DISK_B_0'; VendorSpecific = (New-SmartBuffer -Values ([ordered]@{ 9 = 95 })) }
        }
    }

    It 'returns each disk''s attributes labeled with the disk' {
        $result = @(Get-SmartAttribute)
        $result.Count | Should -Be 3
        @($result | ForEach-Object { '{0}:{1}={2}' -f $_.InstanceName, $_.AttrID, $_.AttrValue }) |
            Should -Be @('DISK_A_0:5=100', 'DISK_A_0:194=40', 'DISK_B_0:9=95')
        Should -Invoke Get-CimInstance -ModuleName StorageHealth -Times 1 -Exactly -ParameterFilter { $Namespace -eq 'root\WMI' }
    }

    It 'throws in a session that is not elevated instead of relaunching powershell.exe' {
        Mock Test-IsAdministrator -ModuleName StorageHealth { $false }
        Mock Start-Process -ModuleName StorageHealth { }
        { Get-SmartAttribute } | Should -Throw '*elevated*'
        Should -Invoke Start-Process -ModuleName StorageHealth -Times 0 -Exactly
        Should -Invoke Get-CimInstance -ModuleName StorageHealth -Times 0 -Exactly
    }
}

Describe 'Get-DriveHealth -Source Wmi' {
    BeforeEach {
        Mock Get-Disk -ModuleName StorageHealth {
            [pscustomobject]@{ FriendlyName = 'Disk A'; SerialNumber = 'SN-A'; BusType = 'SATA'; FirmwareVersion = '1.0'; Path = '\\?\scsi#disk&ven_a#4&aaa&0&000000#{53f56307}' }
            [pscustomobject]@{ FriendlyName = 'Disk B'; SerialNumber = 'SN-B'; BusType = 'NVMe'; FirmwareVersion = '2.0'; Path = '\\?\scsi#disk&ven_b#4&bbb&0&000100#{53f56307}' }
            [pscustomobject]@{ FriendlyName = 'Disk C'; SerialNumber = 'SN-C'; BusType = 'SATA'; FirmwareVersion = '3.0'; Path = '\\?\scsi#disk&ven_c#4&ccc&0&000200#{53f56307}' }
            [pscustomobject]@{ FriendlyName = 'Virtual'; SerialNumber = 'SN-V'; BusType = 'File Backed Virtual'; FirmwareVersion = '0'; Path = '\\?\scsi#disk&ven_v#4&vvv&0&000300#{53f56307}' }
        }
        Mock Get-CimInstance -ModuleName StorageHealth -ParameterFilter { $ClassName -eq 'MSStorageDriver_FailurePredictData' } {
            [pscustomobject]@{ InstanceName = 'SCSI\Disk&Ven_A\4&aaa&0&000000_0'; VendorSpecific = (New-SmartBuffer -Values ([ordered]@{ 5 = 100; 9 = 50; 187 = 99; 188 = 98; 197 = 97; 198 = 96 })) }
            [pscustomobject]@{ InstanceName = 'SCSI\Disk&Ven_B\4&bbb&0&000100_0'; VendorSpecific = (New-SmartBuffer -Values ([ordered]@{ 5 = 80; 187 = 70 })) }
            [pscustomobject]@{ InstanceName = 'SCSI\Disk&Ven_V\4&vvv&0&000300_0'; VendorSpecific = (New-SmartBuffer -Values ([ordered]@{ 5 = 1 })) }
        }
    }

    It 'puts each attribute''s own value in its column' {
        $a = @(Get-DriveHealth) | Where-Object SerialNumber -eq 'SN-A'
        @($a.ReallocatedSectorsCount, $a.ReportedUncorrectableErrors, $a.CommandTimeout, $a.CurrentPendingSectorCount, $a.UncorrectableSectorCount) |
            Should -Be @(100, 99, 98, 97, 96)
        @($a.FriendlyName, $a.BusType, $a.FirmwareVersion) | Should -Be @('Disk A', 'SATA', '1.0')
        $a.DriveLetter | Should -BeNullOrEmpty
    }

    It 'leaves an attribute the disk does not report empty instead of carrying it over' {
        $b = @(Get-DriveHealth) | Where-Object SerialNumber -eq 'SN-B'
        @($b.ReallocatedSectorsCount, $b.ReportedUncorrectableErrors) | Should -Be @(80, 70)
        $b.CommandTimeout | Should -BeNullOrEmpty
        $b.UncorrectableSectorCount | Should -BeNullOrEmpty
    }

    It 'returns objects only for listed bus types with SMART data' {
        @(Get-DriveHealth | ForEach-Object SerialNumber) | Should -Be @('SN-A', 'SN-B')
    }
}

Describe 'Get-DriveHealth -Source Smartctl' {
    BeforeAll {
        $smartctlC = @(
            'smartctl 7.4 2023-08-01 r5530 [x86_64-w64-mingw32-w10-22H2] (sf-7.4-1)'
            'ID# ATTRIBUTE_NAME          FLAG     VALUE WORST THRESH TYPE      UPDATED  WHEN_FAILED RAW_VALUE'
            '  5 Reallocated_Sector_Ct   0x0033   100   100   010    Pre-fail  Always       -       0'
            '187 Reported_Uncorrect      0x0032   099   099   000    Old_age   Always       -       1'
            '188 Command_Timeout         0x0032   098   098   000    Old_age   Always       -       2'
            '197 Current_Pending_Sector  0x0012   097   097   000    Old_age   Always       -       3'
            '198 Offline_Uncorrectable   0x0010   096   096   000    Old_age   Offline      -       4'
        )
        $smartctlD = @(
            '  5 Reallocated_Sector_Ct   0x0033   090   090   010    Pre-fail  Always       -       12'
        )
    }

    BeforeEach {
        Mock Get-CimInstance -ModuleName StorageHealth -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' } {
            [pscustomobject]@{ DeviceID = 'C:' }
            [pscustomobject]@{ DeviceID = 'D:' }
            [pscustomobject]@{ DeviceID = 'E:' }
        }
        Mock Invoke-Smartctl -ModuleName StorageHealth -ParameterFilter { $Device -eq 'C:' } { $smartctlC }
        Mock Invoke-Smartctl -ModuleName StorageHealth -ParameterFilter { $Device -eq 'D:' } { $smartctlD }
        Mock Invoke-Smartctl -ModuleName StorageHealth -ParameterFilter { $Device -eq 'E:' } { 'Read SMART Data failed' }
        Mock Get-Partition -ModuleName StorageHealth { [pscustomobject]@{ DiskNumber = [int][char]"$DriveLetter" - [int][char]'C' } }
        Mock Get-Disk -ModuleName StorageHealth { [pscustomobject]@{ FriendlyName = "Disk $Number"; SerialNumber = "SN-$Number"; BusType = 'SATA'; FirmwareVersion = '1.0' } }
    }

    It 'reports every fixed drive with attributes, not only the last one' {
        $result = @(Get-DriveHealth -Source Smartctl)
        @($result.DriveLetter) | Should -Be @('C:', 'D:')
        Should -Invoke Get-CimInstance -ModuleName StorageHealth -Times 1 -Exactly -ParameterFilter { $Filter -eq 'DriveType=3' }
    }

    It 'reads the VALUE column of each attribute and the disk details once per drive' {
        $result = @(Get-DriveHealth -Source Smartctl)
        $c = $result[0]
        @($c.ReallocatedSectorsCount, $c.ReportedUncorrectableErrors, $c.CommandTimeout, $c.CurrentPendingSectorCount, $c.UncorrectableSectorCount) |
            Should -Be @(100, 99, 98, 97, 96)
        @($c.FriendlyName, $c.SerialNumber) | Should -Be @('Disk 0', 'SN-0')
        $d = $result[1]
        @($d.ReallocatedSectorsCount, $d.SerialNumber) | Should -Be @(90, 'SN-1')
        $d.ReportedUncorrectableErrors | Should -BeNullOrEmpty
        Should -Invoke Get-Partition -ModuleName StorageHealth -Times 2 -Exactly
    }
}

Describe 'Invoke-Smartctl (private)' {
    It 'returns the output for a disk-state exit bit and passes -A and the device' {
        Mock smartctl -ModuleName StorageHealth { $global:LASTEXITCODE = 32; 'attribute table' }
        InModuleScope StorageHealth { Invoke-Smartctl -Device 'C:' } | Should -Be 'attribute table'
        Should -Invoke smartctl -ModuleName StorageHealth -Times 1 -Exactly -ParameterFilter {
            # A stub on macOS and Linux collects the arguments in StubRemainingArguments; a real
            # smartctl gets them in $args.
            ((@($args) + @($StubRemainingArguments) | Where-Object { $_ }) -join " ") -eq "-A C:"
        }
    }

    It 'writes an error for exit bit 2 when no attribute table was printed' {
        Mock smartctl -ModuleName StorageHealth { $global:LASTEXITCODE = 4; 'Read SMART Data failed: Input/output error' }
        $result = InModuleScope StorageHealth { $out = Invoke-Smartctl -Device 'C:' -ErrorVariable err -ErrorAction SilentlyContinue; [pscustomobject]@{ Out = $out; Err = $err } }
        $result.Out | Should -BeNullOrEmpty
        "$($result.Err)" | Should -Match 'smartctl -A C: failed with exit code 4: Read SMART Data failed'
    }

    It 'returns the table for exit bit 2 when the attribute table was still printed' {
        Mock smartctl -ModuleName StorageHealth {
            $global:LASTEXITCODE = 4 + 32
            'Warning! SMART Attribute Data Structure error: invalid SMART checksum.'
            'ID# ATTRIBUTE_NAME          FLAG     VALUE WORST THRESH TYPE      UPDATED  WHEN_FAILED RAW_VALUE'
            '  9 Power_On_Hours          0x0032   099   099   000    Old_age   Always       -       1234'
        }
        $result = InModuleScope StorageHealth { $out = Invoke-Smartctl -Device 'C:' -ErrorVariable err -ErrorAction SilentlyContinue; [pscustomobject]@{ Out = $out; Err = $err } }
        @($result.Out).Count | Should -Be 3
        $result.Err | Should -BeNullOrEmpty
    }

    It 'writes an error when smartctl cannot open the device' {
        Mock smartctl -ModuleName StorageHealth { $global:LASTEXITCODE = 2; 'Smartctl open device: C: failed' }
        $result = InModuleScope StorageHealth { Invoke-Smartctl -Device 'C:' -ErrorVariable err -ErrorAction SilentlyContinue; $err }
        "$result" | Should -Match 'smartctl -A C: failed with exit code 2'
    }
}

Describe 'Test-IsAdministrator (private)' {
    It 'returns a boolean on Windows' -Skip:($env:OS -ne 'Windows_NT') {
        InModuleScope StorageHealth { Test-IsAdministrator } | Should -BeOfType [bool]
    }
}

Describe 'Get-DriveHealthStats2-Sensor.ps1 wrapper' {
    BeforeAll {
        $sensor = Join-Path $repoRoot 'Scripts/FileSystem/Get-DriveHealthStats2-Sensor.ps1'
    }

    It 'prints one eight-field sensor-error line and exits 1 when StorageHealth cannot be loaded' {
        # Runs the real sensor, copied to a folder with no Modules beside it, in a child
        # PowerShell whose PSModulePath holds no StorageHealth. Mirrors a pasted sensor body.
        $folder = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $folder
        $copy = Join-Path $folder 'Get-DriveHealthStats2-Sensor.ps1'
        Copy-Item -LiteralPath $sensor -Destination $copy
        $powershell = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $output = @(& $powershell -NoProfile -Command "`$env:PSModulePath = '$folder'; & '$copy'; exit `$LASTEXITCODE" 2>$null)
        $LASTEXITCODE | Should -Be 1
        $output.Count | Should -Be 1
        $output[0] | Should -Match '^StorageHealth module not found\|Sensor error\|'
        $output[0].Split('|').Count | Should -Be 8 -Because 'an error line has the same columns as a drive line'
    }

    Context 'with a stub StorageHealth module' {
        BeforeAll {
            # Runs the real sensor, copied away from the repository's Modules folder, against a
            # stub StorageHealth found first on PSModulePath, so Get-DriveHealth's behavior is set.
            function Invoke-SensorWithStub {
                param([string]$GetDriveHealthBody)
                $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
                $moduleFolder = Join-Path $root 'StorageHealth'
                $null = New-Item -ItemType Directory -Path $moduleFolder
                Set-Content -LiteralPath (Join-Path $moduleFolder 'StorageHealth.psm1') -Value (
                    "function Get-DriveHealth { [CmdletBinding()] param([string]`$Source) $GetDriveHealthBody }")
                $copy = Join-Path $root 'Get-DriveHealthStats2-Sensor.ps1'
                Copy-Item -LiteralPath $sensor -Destination $copy
                $powershell = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
                $command = "`$env:PSModulePath = '$root' + [IO.Path]::PathSeparator + `$env:PSModulePath; & '$copy'; exit `$LASTEXITCODE"
                $output = @(& $powershell -NoProfile -Command $command 2>$null)
                [pscustomobject]@{ Output = $output; ExitCode = $LASTEXITCODE }
            }
            $goodDrive = "[pscustomobject]@{ DriveLetter = 'C:'; FriendlyName = 'Disk0'; SerialNumber = 'S0'; " +
                "ReallocatedSectorsCount = 100; ReportedUncorrectableErrors = 99; CommandTimeout = 98; " +
                "CurrentPendingSectorCount = 97; UncorrectableSectorCount = 96 }"
        }

        It 'prints each drive and exits 0 when every drive is read' {
            $result = Invoke-SensorWithStub -GetDriveHealthBody $goodDrive
            $result.ExitCode | Should -Be 0
            $result.Output | Should -Be @('C:|Disk0|S0|100|99|98|97|96')
        }

        It 'still prints the readable drives, then an error line per unreadable drive, and exits 1' {
            $result = Invoke-SensorWithStub -GetDriveHealthBody (
                "$goodDrive; Write-Error 'smartctl -A D: failed with exit code 2: open failed'")
            $result.ExitCode | Should -Be 1
            $result.Output.Count | Should -Be 2
            $result.Output[0] | Should -Be 'C:|Disk0|S0|100|99|98|97|96'
            $result.Output[1] | Should -Match '^Drive health could not be read\|Sensor error\|smartctl -A D: failed'
            $result.Output[1].Split('|').Count | Should -Be 8
        }

        It 'prints one error line and exits 1 when the drive list cannot be read at all' {
            $result = Invoke-SensorWithStub -GetDriveHealthBody "throw 'Get-Partition is not available'"
            $result.ExitCode | Should -Be 1
            $result.Output.Count | Should -Be 1
            $result.Output[0] | Should -Match '^Drive health could not be read\|Sensor error\|Get-Partition is not available'
            $result.Output[0].Split('|').Count | Should -Be 8
        }
    }
}

Describe 'Test-SSD' {
    It 'returns <Expected> when rotation rate is <Rotation> and seek penalty is <Seek>' -ForEach @(
        @{ Rotation = $true; Seek = $true; Expected = $false }
        @{ Rotation = $false; Seek = $true; Expected = $true }
        @{ Rotation = $true; Seek = $false; Expected = $true }
        @{ Rotation = $false; Seek = $false; Expected = $true }
    ) {
        $r = $Rotation
        $s = $Seek
        Mock Invoke-SsdNativeCheck -ModuleName StorageHealth -ParameterFilter { $Check -eq 'HasNominalMediaRotationRate' } { $r }
        Mock Invoke-SsdNativeCheck -ModuleName StorageHealth -ParameterFilter { $Check -eq 'HasSeekPenalty' } { $s }
        $result = Test-SSD -PhysicalDiskId 1 -Confirm:$false
        $result | Should -BeOfType [bool]
        $result | Should -Be $Expected
        Should -Invoke Invoke-SsdNativeCheck -ModuleName StorageHealth -Times 2 -Exactly -ParameterFilter { $DriveString -eq '\\.\PhysicalDrive1' }
    }

    It 'counts a failed check as a spinning disk and lets the other check decide' {
        Mock Invoke-SsdNativeCheck -ModuleName StorageHealth -ParameterFilter { $Check -eq 'HasNominalMediaRotationRate' } { throw 'Access is denied' }
        Mock Invoke-SsdNativeCheck -ModuleName StorageHealth -ParameterFilter { $Check -eq 'HasSeekPenalty' } { $false }
        Test-SSD -PhysicalDiskId 0 -Confirm:$false | Should -BeTrue
        Mock Invoke-SsdNativeCheck -ModuleName StorageHealth -ParameterFilter { $Check -eq 'HasSeekPenalty' } { throw 'Access is denied' }
        Test-SSD -PhysicalDiskId 0 -Confirm:$false | Should -BeFalse
    }

    It 'returns one result per disk number from the pipeline' {
        Mock Invoke-SsdNativeCheck -ModuleName StorageHealth { $DriveString -ne '\\.\PhysicalDrive2' }
        $result = @(0, 2 | Test-SSD -Confirm:$false)
        $result | Should -Be @($false, $true)
    }

    It 'calls nothing and reports a spinning disk for each disk under -WhatIf' {
        Mock Invoke-SsdNativeCheck -ModuleName StorageHealth { $false }
        @(0, 1 | Test-SSD -WhatIf) | Should -Be @($false, $false)
        Should -Invoke Invoke-SsdNativeCheck -ModuleName StorageHealth -Times 0 -Exactly
    }
}

Describe 'Invoke-SsdNativeCheck (private)' {
    It 'compiles the detection class with both public checks' {
        $type = InModuleScope StorageHealth {
            if (-not ('Util.DetectSSD' -as [type])) { Add-Type -TypeDefinition (Get-SsdNativeSource) }
            [type]'Util.DetectSSD'
        }
        foreach ($name in 'HasSeekPenalty', 'HasNominalMediaRotationRate') {
            $method = $type.GetMethod($name)
            $method | Should -Not -BeNullOrEmpty -Because "$name is called by Invoke-SsdNativeCheck"
            $method.IsStatic | Should -BeTrue
            $method.ReturnType | Should -Be ([bool])
        }
    }

    It 'rejects an unknown check name' {
        { InModuleScope StorageHealth { Invoke-SsdNativeCheck -Check 'Bogus' -DriveString '\\.\PhysicalDrive0' } } | Should -Throw
    }
}
