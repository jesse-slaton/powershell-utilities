BeforeDiscovery {
    $script:OnWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    $script:ScriptPath = Resolve-ScriptUnderTest -Name $PSCommandPath
    . (Get-ScriptFunctionDefinition -Path $script:ScriptPath)

    $script:Now = [datetime]'2026-06-15T12:00:00'

    # Splits a file time into endTimeHi/endTimeLo as the registry returns them: two signed
    # REG_DWORD (Int32) values.
    function ConvertTo-GpEndTime {
        param([Int64]$FileTime)
        $Low = $FileTime -band [Int64]4294967295
        if ($Low -ge [Int64]2147483648) { $Low -= [Int64]4294967296 }
        [pscustomobject]@{
            endTimeHi = [Int32]($FileTime -shr 32)
            endTimeLo = [Int32]$Low
        }
    }

    function Set-LastRefresh {
        param([timespan]$Ago)
        $script:State = ConvertTo-GpEndTime -FileTime ($script:Now - $Ago).ToFileTime()
    }
}

Describe 'Get-LastComputerPolicyRefresh' {
    BeforeEach {
        Mock Get-LocalMachineRegistryValue { $script:State.$Name } -ParameterFilter { $SubKey -eq 'SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Extension-List\{00000000-0000-0000-0000-000000000000}' }
        Mock Get-ItemProperty { throw 'Get-ItemProperty must not be called' }
        Mock Invoke-Command { throw 'Invoke-Command must not be called' }
    }

    It 'reports <Expected> for a refresh <Ago> ago' -TestCases @(
        @{ Ago = [timespan]'00:30:00'; Expected = 'Less than 1 hour' }
        @{ Ago = [timespan]'01:10:00'; Expected = '1 hour' }
        @{ Ago = [timespan]'05:00:00'; Expected = '5 hours' }
        @{ Ago = [timespan]'23:59:00'; Expected = '23 hours' }
        @{ Ago = [timespan]'1.00:00:00'; Expected = '1 day' }
        @{ Ago = [timespan]'1.23:59:00'; Expected = '1 day' }
        @{ Ago = [timespan]'2.00:00:00'; Expected = '2 days' }
        @{ Ago = [timespan]'3.04:00:00'; Expected = '3 days' }
        @{ Ago = [timespan]'364.00:00:00'; Expected = '364 days' }
        @{ Ago = [timespan]'400.00:00:00'; Expected = 'Over 1 year' }
    ) {
        Set-LastRefresh -Ago $Ago

        Get-LastComputerPolicyRefresh -Now $script:Now | Should -Be $Expected
    }

    It 'combines a low DWORD that has its top bit set without sign-extending it' {
        # Force bit 31 of the low half on: the registry hands this back as a negative Int32.
        $FileTime = (($script:Now - [timespan]'3.12:00:00').ToFileTime()) -bor [Int64]2147483648
        $script:State = ConvertTo-GpEndTime -FileTime $FileTime
        $script:State.endTimeLo | Should -BeLessThan 0

        Get-LastComputerPolicyRefresh -Now $script:Now | Should -Be '3 days'
    }

    It 'reports the failure text when the values are missing' {
        $script:State = [pscustomobject]@{ endTimeHi = 1 }

        Get-LastComputerPolicyRefresh -Now $script:Now | Should -Be 'Could not get last GPUpdate datetime'
    }

    It 'reports the failure text when the key cannot be read' {
        # Valid values, so only the read failure can produce the failure text. The filter
        # makes this mock outrank the filtered one from BeforeEach.
        Set-LastRefresh -Ago ([timespan]'02:00:00')
        Mock Get-LocalMachineRegistryValue { throw 'Requested registry access is not allowed.' } -ParameterFilter { $true }

        Get-LastComputerPolicyRefresh -Now $script:Now | Should -Be 'Could not get last GPUpdate datetime'
    }

    It 'reads the registry in-process, with no loopback remoting' {
        Set-LastRefresh -Ago ([timespan]'02:00:00')

        Get-LastComputerPolicyRefresh -Now $script:Now | Should -Be '2 hours'
        Should -Invoke Get-LocalMachineRegistryValue -Times 2 -Exactly
        Should -Invoke Get-ItemProperty -Times 0 -Exactly
        Should -Invoke Invoke-Command -Times 0 -Exactly
    }
}

Describe 'Get-LocalMachineRegistryValue' {
    # Read-only reads of the real registry, so these run only on Windows.
    It 'reads a value from the 64-bit HKLM view' -Skip:(-not $script:OnWindows) {
        Get-LocalMachineRegistryValue -SubKey 'SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'CurrentBuild' | Should -Match '^\d+$'
    }

    It 'returns $null for a missing key' -Skip:(-not $script:OnWindows) {
        Get-LocalMachineRegistryValue -SubKey 'SOFTWARE\PesterMissingKey-0f3c0738' -Name 'Anything' | Should -BeNullOrEmpty
    }
}

Describe 'GetLastComputerPolicyRefresh.ps1' {
    It 'never calls Invoke-Command' {
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$null)
        $Names = @($Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() })
        $Names | Should -Not -Contain 'Invoke-Command'
    }

    It 'opens HKLM through the 64-bit registry view so a 32-bit host is not redirected' {
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$null)
        $Calls = @($Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'OpenBaseKey' }, $true))
        $Calls.Count | Should -Be 1
        $Calls[0].Arguments.Count | Should -Be 2
        $Calls[0].Arguments[0].Extent.Text | Should -Be '[Microsoft.Win32.RegistryHive]::LocalMachine'
        $Calls[0].Arguments[1].Extent.Text | Should -Be '[Microsoft.Win32.RegistryView]::Registry64'
    }
}
