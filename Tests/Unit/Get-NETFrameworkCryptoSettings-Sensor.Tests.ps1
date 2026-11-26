BeforeDiscovery {
    $script:OnWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    $script:ScriptPath = Resolve-ScriptUnderTest -Name $PSCommandPath
    . (Get-ScriptFunctionDefinition -Path $script:ScriptPath)
}

Describe 'Get-NetFrameworkCryptoSetting' {
    It 'writes SystemDefaultTlsVersions|SchUseStrongCrypto for each key in order' {
        Mock Get-LocalMachineRegistryValue {
            $Values = @{
                'SOFTWARE\Microsoft\.NETFramework\v2.0.50727|SystemDefaultTlsVersions'             = 1
                'SOFTWARE\Microsoft\.NETFramework\v2.0.50727|SchUseStrongCrypto'                   = 0
                'SOFTWARE\Wow6432node\Microsoft\.NETFramework\v2.0.50727|SchUseStrongCrypto'       = 1
                'SOFTWARE\Microsoft\.NETFramework\v4.0.30319|SystemDefaultTlsVersions'             = 1
                'SOFTWARE\Microsoft\.NETFramework\v4.0.30319|SchUseStrongCrypto'                   = 1
                'SOFTWARE\Wow6432node\Microsoft\.NETFramework\v4.0.30319|SystemDefaultTlsVersions' = 2
            }
            $Values["$SubKey|$Name"]
        }

        Get-NetFrameworkCryptoSetting | Should -Be 'True|False|False|True|True|True|False|False'
    }

    It 'reports False for every value when the keys are missing' {
        Mock Get-LocalMachineRegistryValue { $null }

        Get-NetFrameworkCryptoSetting | Should -Be 'False|False|False|False|False|False|False|False'
    }

    It 'reads all eight values through Get-LocalMachineRegistryValue' {
        Mock Get-LocalMachineRegistryValue { 1 }

        Get-NetFrameworkCryptoSetting | Should -Be 'True|True|True|True|True|True|True|True'
        Should -Invoke Get-LocalMachineRegistryValue -Times 8 -Exactly
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

Describe 'Get-NETFrameworkCryptoSettings-Sensor.ps1' {
    It 'opens HKLM through the 64-bit registry view so a 32-bit host is not redirected' {
        # Checks the code, not the help text: every OpenBaseKey call must pass
        # LocalMachine and RegistryView.Registry64.
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$null)
        $Calls = @($Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'OpenBaseKey' }, $true))
        $Calls.Count | Should -Be 1
        $Calls[0].Arguments.Count | Should -Be 2
        $Calls[0].Arguments[0].Extent.Text | Should -Be '[Microsoft.Win32.RegistryHive]::LocalMachine'
        $Calls[0].Arguments[1].Extent.Text | Should -Be '[Microsoft.Win32.RegistryView]::Registry64'
        @($Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -match '^Get-Item(Property)?$|^Get-ChildItem$' }, $true)) | Should -BeNullOrEmpty
    }

    It 'never launches powershell.exe or another PowerShell' {
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$null)
        $Names = @($Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() })
        $Strings = @($Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst] }, $true) | ForEach-Object { $_.Value })
        $Names + $Strings | Where-Object { $_ -match 'powershell(\.exe)?$|pwsh|sysnative' } | Should -BeNullOrEmpty
        @($Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.InvocationOperator -ne 'Unknown' }, $true)) | Should -BeNullOrEmpty
    }
}
