#Requires -Version 5.1
# Behavior tests for Modules/OfficeC2R. The module is imported (it only defines functions);
# every registry read goes through Get-OfficeC2RConfigurationValue, which is mocked, so these
# run on any OS. The one test of that helper itself reads the real registry and runs only on
# Windows.

BeforeDiscovery {
    $script:onWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'Modules/OfficeC2R/OfficeC2R.psd1') -Force
}

AfterAll {
    Remove-Module -Name OfficeC2R -Force -ErrorAction SilentlyContinue
}

Describe 'Get-OfficeC2RConfigurationValue' {
    It 'returns $null or a hashtable without throwing for a value that does not exist' -Skip:(-not $script:onWindows) {
        $result = & (Get-Module OfficeC2R) { Get-OfficeC2RConfigurationValue -Name 'NoSuchValue-OfficeC2RTests' }
        if ($null -ne $result) {
            $result | Should -BeOfType [hashtable]
            $result.ContainsKey('NoSuchValue-OfficeC2RTests') | Should -BeTrue
            $result['NoSuchValue-OfficeC2RTests'] | Should -BeNullOrEmpty
        }
    }

    # The module's promise is the 64-bit view even from a 32-bit host, where the default
    # view is redirected to WOW6432Node. That cannot be exercised off a 32-bit Windows host,
    # so this checks the code: every OpenBaseKey call in the module passes Registry64, and
    # the helper does not read through the registry provider, which follows the host's view.
    It 'opens HKLM through the 64-bit registry view so a 32-bit host is not redirected' {
        $moduleRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Modules/OfficeC2R'
        $calls = @(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File -Include '*.ps1', '*.psm1' | ForEach-Object {
                $fileAst = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$null)
                $fileAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'OpenBaseKey' }, $true)
            })
        $calls.Count | Should -BeGreaterThan 0
        foreach ($call in $calls) {
            $call.Arguments.Count | Should -Be 2
            $call.Arguments[1].Extent.Text | Should -Be '[Microsoft.Win32.RegistryView]::Registry64'
        }
        $helperAst = (& (Get-Module OfficeC2R) { Get-Command -Name Get-OfficeC2RConfigurationValue }).ScriptBlock.Ast
        @($helperAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -match '^Get-Item(Property)?$|^Get-ChildItem$' }, $true)) | Should -BeNullOrEmpty
    }

    # An access-denied OpenSubKey throws inside the helper's try/finally. Without Stop that
    # .NET exception is only statement-terminating and never reaches the caller's catch, so
    # the caller reports "not installed". That cannot be reproduced off Windows (the registry
    # API fails earlier there), so this checks the helper still sets the preference.
    It '<Helper> makes every failure terminating' -ForEach @(
        @{ Helper = 'Get-OfficeC2RConfigurationValue' }
    ) {
        $ast = (& (Get-Module OfficeC2R) { param($n) Get-Command -Name $n } $Helper).ScriptBlock.Ast
        $stop = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left.Extent.Text -eq '$ErrorActionPreference' -and
                $node.Right.Extent.Text -eq "'Stop'"
            }, $true)
        @($stop).Count | Should -Be 1
    }
}

Describe 'Get-OfficeC2RChannel' {
    It 'outputs <Channel> for its CDNBaseUrl' -ForEach @(
        @{ Guid = '55336b82-a18d-4dd6-b5f6-9e5095c314a6'; Channel = 'Monthly Enterprise Channel' }
        @{ Guid = '492350f6-3a01-4f97-b9c0-c7c6ddf67d60'; Channel = 'Current Channel' }
        @{ Guid = '64256afe-f5d9-4f86-8936-8840a6a4f5be'; Channel = 'Current Channel (Preview)' }
        @{ Guid = '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114'; Channel = 'Semi-Annual Enterprise Channel' }
        @{ Guid = 'b8f9b850-328d-4355-9145-c59439a0c4cf'; Channel = 'Semi-Annual Enterprise Channel (Preview)' }
        @{ Guid = '5440fd1f-7ecb-4221-8110-145efaa6372f'; Channel = 'Beta Channel' }
        @{ Guid = 'ea4a4090-de26-49d7-93c1-91bff9e53fc3'; Channel = 'DevMain Channel' }
    ) {
        Mock Get-OfficeC2RConfigurationValue -ModuleName OfficeC2R { @{ CDNBaseUrl = "http://officecdn.microsoft.com/pr/$Guid" } }
        Get-OfficeC2RChannel | Should -Be $Channel
        Should -Invoke Get-OfficeC2RConfigurationValue -ModuleName OfficeC2R -Times 1 -Exactly -ParameterFilter { $Name -contains 'CDNBaseUrl' }
    }

    It 'matches an https URL with a trailing slash and upper-case GUID' {
        Mock Get-OfficeC2RConfigurationValue -ModuleName OfficeC2R { @{ CDNBaseUrl = 'https://officecdn.microsoft.com/pr/492350F6-3A01-4F97-B9C0-C7C6DDF67D60/' } }
        Get-OfficeC2RChannel | Should -Be 'Current Channel'
    }

    It 'outputs an unknown-channel line naming the URL for any other value' {
        $other = 'http://officecdn.microsoft.com/pr/00000000-0000-0000-0000-000000000000'
        Mock Get-OfficeC2RConfigurationValue -ModuleName OfficeC2R { @{ CDNBaseUrl = $other } }
        Get-OfficeC2RChannel | Should -Be "Unknown Channel - CDNBaseUrl: $other"
    }

    It 'writes an error and outputs nothing when <Case>' -ForEach @(
        @{ Case = 'the Configuration key is missing'; Config = $null; Pattern = 'not found' }
        @{ Case = 'CDNBaseUrl is not set'; Config = @{ CDNBaseUrl = $null }; Pattern = 'CDNBaseUrl value is not set' }
    ) {
        Mock Get-OfficeC2RConfigurationValue -ModuleName OfficeC2R { $Config }
        $result = Get-OfficeC2RChannel -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$err" | Should -Match $Pattern
    }

    It 'writes the registry error, not a not-installed one, when the read fails' {
        Mock Get-OfficeC2RConfigurationValue -ModuleName OfficeC2R { throw [System.UnauthorizedAccessException]::new('Access to the registry key is denied.') }
        $result = Get-OfficeC2RChannel -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$err" | Should -Match 'registry key is denied'
        "$err" | Should -Not -Match 'may not be installed'
    }

    It 'reports a failing real registry read once, as itself' -Skip:$script:onWindows {
        $result = Get-OfficeC2RChannel -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        $err | Should -Not -BeNullOrEmpty
        "$err" | Should -Not -Match 'may not be installed'
    }

    It 'still answers to the Get-Office365Channel alias' {
        Mock Get-OfficeC2RConfigurationValue -ModuleName OfficeC2R { @{ CDNBaseUrl = 'http://officecdn.microsoft.com/pr/5440fd1f-7ecb-4221-8110-145efaa6372f' } }
        Get-Office365Channel | Should -Be 'Beta Channel'
    }
}
