#Requires -Version 5.1
# Behavior tests for Modules/StorageHealth. The module is imported (it only defines functions);
# every CIM call is mocked, so these run on any OS. Windows-only commands are
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
    Import-Module (Join-Path $repoRoot 'Modules/StorageHealth/StorageHealth.psd1') -Force
}

AfterAll {
    Remove-Module -Name StorageHealth -Force -ErrorAction SilentlyContinue
    Remove-CommandStub -Name Get-CimInstance
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
}
