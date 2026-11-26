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
        @{ Helper = 'Write-OfficeC2RConfigurationValue' }
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

Describe 'Get-OfficeC2RBitness' {
    It 'outputs <Expected> for Platform <Platform>' -ForEach @(
        @{ Platform = 'x86'; Expected = '32-bit' }
        @{ Platform = 'x64'; Expected = '64-bit' }
        @{ Platform = 'arm64'; Expected = 'Unknown Office Platform: arm64' }
    ) {
        Mock Get-OfficeC2RConfigurationValue -ModuleName OfficeC2R { @{ Platform = $Platform } }
        Get-OfficeC2RBitness | Should -Be $Expected
        Should -Invoke Get-OfficeC2RConfigurationValue -ModuleName OfficeC2R -Times 1 -Exactly -ParameterFilter { $Name -contains 'Platform' }
    }

    It 'writes an error and outputs nothing when <Case>' -ForEach @(
        @{ Case = 'the Configuration key is missing'; Config = $null; Pattern = 'not found' }
        @{ Case = 'Platform is not set'; Config = @{ Platform = $null }; Pattern = 'Platform value is not set' }
    ) {
        Mock Get-OfficeC2RConfigurationValue -ModuleName OfficeC2R { $Config }
        $result = Get-OfficeC2RBitness -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$err" | Should -Match $Pattern
    }

    It 'writes the registry error, not a not-installed one, when the read fails' {
        Mock Get-OfficeC2RConfigurationValue -ModuleName OfficeC2R { throw [System.UnauthorizedAccessException]::new('Access to the registry key is denied.') }
        $result = Get-OfficeC2RBitness -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$err" | Should -Match 'registry key is denied'
        "$err" | Should -Not -Match 'may not be installed'
    }

    It 'still answers to the Get-OfficeClickToRunBitness alias' {
        Mock Get-OfficeC2RConfigurationValue -ModuleName OfficeC2R { @{ Platform = 'x64' } }
        Get-OfficeClickToRunBitness | Should -Be '64-bit'
    }
}

Describe 'Get-Bitness' {
    It 'outputs <Expected> when the pointer size is <Size>' -ForEach @(
        @{ Size = 4; Expected = 'x86' }
        @{ Size = 8; Expected = 'x64' }
        @{ Size = 16; Expected = 'Unknown' }
    ) {
        Mock Get-OfficeC2RPointerSize -ModuleName OfficeC2R { $Size }
        Get-Bitness | Should -Be $Expected
    }

    It 'reports the real pointer size of this process' {
        $expected = if ([IntPtr]::Size -eq 8) { 'x64' } else { 'x86' }
        Get-Bitness | Should -Be $expected
    }
}

Describe 'Get-OfficeC2RVersion' {
    BeforeAll {
        # releaseDate in the list's own 'yyyy MMM dd' form; endOfSupportDate in ISO 8601,
        # which ConvertFrom-Json types as [datetime] on PowerShell 7 but not on 5.1. The
        # third entry has an ISO releaseDate, the form that broke ParseExact on 7.
        $script:listJson = @'
{ "data": [
  { "version": "2408", "channel": "Current Channel", "build": "17928.20114", "fullBuild": "16.0.17928.20114", "releaseDate": "2024 Aug 27", "endOfSupportDate": "2025-02-11T00:00:00" },
  { "version": "2402", "channel": "Semi-Annual Enterprise Channel", "build": "17328.20550", "fullBuild": "16.0.17328.20550", "releaseDate": "2024 Aug 13", "endOfSupportDate": "N/A" },
  { "version": "2408", "channel": "Monthly Enterprise Channel", "build": "17928.20114", "fullBuild": "16.0.17928.20114", "releaseDate": "2024-09-10T00:00:00", "endOfSupportDate": "" }
] }
'@
    }

    BeforeEach {
        Mock Get-OfficeC2RConfigurationValue -ModuleName OfficeC2R { @{ VersionToReport = '16.0.17928.20114' } }
        Mock Invoke-WebRequest -ModuleName OfficeC2R { [pscustomobject]@{ Content = $script:listJson } }
    }

    It 'outputs one typed object per entry matching the installed build' {
        $result = @(Get-OfficeC2RVersion)
        $result.Count | Should -Be 2
        $result[0].Version | Should -Be '2408'
        $result[0].Channel | Should -Be 'Current Channel'
        $result[0].Build | Should -BeOfType [version]
        $result[0].Build | Should -Be ([version]'17928.20114')
        $result[0].ReleaseDate | Should -BeOfType [datetime]
        $result[0].ReleaseDate.Date | Should -Be ([datetime]'2024-08-27')
        $result[1].Channel | Should -Be 'Monthly Enterprise Channel'
        Should -Invoke Invoke-WebRequest -ModuleName OfficeC2R -Times 1 -Exactly -ParameterFilter { $Uri -match 'office365versions\.com/api/getjson\?name=all' }
    }

    It 'types ISO 8601 dates as [datetime] on every edition and keeps other text' {
        $result = @(Get-OfficeC2RVersion)
        $result[0].EndOfSupportDate | Should -BeOfType [datetime]
        $result[0].EndOfSupportDate.Date | Should -Be ([datetime]'2025-02-11')
        $result[1].ReleaseDate | Should -BeOfType [datetime]
        $result[1].ReleaseDate.Date | Should -Be ([datetime]'2024-09-10')
        $result[1].EndOfSupportDate | Should -BeNullOrEmpty
    }

    It 'outputs nothing when no entry matches' {
        Mock Get-OfficeC2RConfigurationValue -ModuleName OfficeC2R { @{ VersionToReport = '16.0.1.1' } }
        Get-OfficeC2RVersion | Should -BeNullOrEmpty
    }

    It 'writes an error and downloads nothing when <Case>' -ForEach @(
        @{ Case = 'the Configuration key is missing'; Config = $null; Pattern = 'not found' }
        @{ Case = 'VersionToReport is not set'; Config = @{ VersionToReport = $null }; Pattern = 'VersionToReport value is not set' }
        @{ Case = 'VersionToReport is not a version'; Config = @{ VersionToReport = 'garbage' }; Pattern = "not a version: 'garbage'" }
    ) {
        Mock Get-OfficeC2RConfigurationValue -ModuleName OfficeC2R { $Config }
        $result = Get-OfficeC2RVersion -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$err" | Should -Match $Pattern
        Should -Invoke Invoke-WebRequest -ModuleName OfficeC2R -Times 0 -Exactly
    }

    It 'writes the registry error, not a not-installed one, and downloads nothing when the read fails' {
        Mock Get-OfficeC2RConfigurationValue -ModuleName OfficeC2R { throw [System.UnauthorizedAccessException]::new('Access to the registry key is denied.') }
        $result = Get-OfficeC2RVersion -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$err" | Should -Match 'registry key is denied'
        "$err" | Should -Not -Match 'may not be installed'
        Should -Invoke Invoke-WebRequest -ModuleName OfficeC2R -Times 0 -Exactly
    }

    It 'throws when the download fails' {
        Mock Invoke-WebRequest -ModuleName OfficeC2R { throw 'no network' }
        { Get-OfficeC2RVersion } | Should -Throw '*no network*'
    }
}

Describe 'Set-OfficeC2RChannel' {
    BeforeEach {
        Mock Test-Path -ModuleName OfficeC2R { $true }
        Mock Write-OfficeC2RConfigurationValue -ModuleName OfficeC2R
        Mock Start-Process -ModuleName OfficeC2R { [pscustomobject]@{ ExitCode = 0 } }
    }

    It 'writes only the <Channel> CDN URL, then runs the update' -ForEach @(
        @{ Channel = 'Current'; Guid = '492350f6-3a01-4f97-b9c0-c7c6ddf67d60' }
        @{ Channel = 'MonthlyEnterprise'; Guid = '55336b82-a18d-4dd6-b5f6-9e5095c314a6' }
        @{ Channel = 'SemiAnnual'; Guid = '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114' }
        @{ Channel = 'Beta'; Guid = '5440fd1f-7ecb-4221-8110-145efaa6372f' }
    ) {
        $result = Set-OfficeC2RChannel -OfficeChannel $Channel
        $url = "http://officecdn.microsoft.com/pr/$Guid"
        $result.Channel | Should -Be $Channel
        $result.UpdateChannel | Should -Be $url
        $result.ExitCode | Should -Be 0
        Should -Invoke Write-OfficeC2RConfigurationValue -ModuleName OfficeC2R -Times 1 -Exactly -ParameterFilter { $Name -eq 'UpdateChannel' -and $Value -eq $url }
        Should -Invoke Write-OfficeC2RConfigurationValue -ModuleName OfficeC2R -Times 1 -Exactly
        Should -Invoke Start-Process -ModuleName OfficeC2R -Times 1 -Exactly -ParameterFilter {
            $FilePath -match 'ClickToRun\\OfficeC2RClient\.exe$' -and "$ArgumentList" -eq '/update user displaylevel=false forceappshutdown=true' -and $Wait -and $PassThru
        }
    }

    It 'maps <Channel> to the URL Get-OfficeC2RChannel names <Name>' -ForEach @(
        @{ Channel = 'Current'; Name = 'Current Channel' }
        @{ Channel = 'MonthlyEnterprise'; Name = 'Monthly Enterprise Channel' }
        @{ Channel = 'SemiAnnual'; Name = 'Semi-Annual Enterprise Channel' }
        @{ Channel = 'Beta'; Name = 'Beta Channel' }
    ) {
        $url = (Set-OfficeC2RChannel -OfficeChannel $Channel).UpdateChannel
        Mock Get-OfficeC2RConfigurationValue -ModuleName OfficeC2R { @{ CDNBaseUrl = $url } }
        Get-OfficeC2RChannel | Should -Be $Name
    }

    It 'defaults to SemiAnnual' {
        (Set-OfficeC2RChannel).Channel | Should -Be 'SemiAnnual'
    }

    It 'warns for exit code <Code>' -ForEach @(
        @{ Code = 1601; Pattern = 'already in progress' }
        @{ Code = 1704; Pattern = 'suspended' }
        @{ Code = 3010; Pattern = 'reboot' }
    ) {
        Mock Start-Process -ModuleName OfficeC2R { [pscustomobject]@{ ExitCode = $Code } }
        $result = Set-OfficeC2RChannel -OfficeChannel Current -WarningVariable warn -WarningAction SilentlyContinue
        $result.ExitCode | Should -Be $Code
        "$warn" | Should -Match $Pattern
    }

    It 'writes an error for any other exit code and still outputs the result' {
        Mock Start-Process -ModuleName OfficeC2R { [pscustomobject]@{ ExitCode = 17002 } }
        $result = Set-OfficeC2RChannel -OfficeChannel Current -ErrorVariable err -ErrorAction SilentlyContinue
        $result.ExitCode | Should -Be 17002
        "$err" | Should -Match 'failed with exit code 17002'
    }

    It 'changes nothing when OfficeC2RClient.exe is missing' {
        Mock Test-Path -ModuleName OfficeC2R { $false }
        $result = Set-OfficeC2RChannel -OfficeChannel Current -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$err" | Should -Match 'OfficeC2RClient\.exe not found'
        Should -Invoke Write-OfficeC2RConfigurationValue -ModuleName OfficeC2R -Times 0 -Exactly
        Should -Invoke Start-Process -ModuleName OfficeC2R -Times 0 -Exactly
    }

    It 'runs OfficeC2RClient.exe from the 32-bit Common Files folder when only that one exists' {
        Mock Test-Path -ModuleName OfficeC2R { $LiteralPath -like '*Program Files (x86)*' }
        $result = Set-OfficeC2RChannel -OfficeChannel Current
        $result.ExitCode | Should -Be 0
        Should -Invoke Start-Process -ModuleName OfficeC2R -Times 1 -Exactly -ParameterFilter {
            $FilePath -like '*Program Files (x86)\Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe'
        }
    }

    It 'names every folder it tried when OfficeC2RClient.exe is missing' {
        Mock Test-Path -ModuleName OfficeC2R { $false }
        Set-OfficeC2RChannel -OfficeChannel Current -ErrorVariable err -ErrorAction SilentlyContinue
        "$err" | Should -Match ([regex]::Escape('Program Files\Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe'))
        "$err" | Should -Match ([regex]::Escape('Program Files (x86)\Common Files\microsoft shared\ClickToRun\OfficeC2RClient.exe'))
    }

    It 'does not run the update when the registry write fails' {
        Mock Write-OfficeC2RConfigurationValue -ModuleName OfficeC2R { throw [System.UnauthorizedAccessException]::new('Access to the registry key is denied.') }
        $result = Set-OfficeC2RChannel -OfficeChannel Current -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$err" | Should -Match 'Unable to set UpdateChannel.*registry key is denied'
        Should -Invoke Start-Process -ModuleName OfficeC2R -Times 0 -Exactly
    }

    It 'writes an error and outputs nothing when OfficeC2RClient.exe does not start' {
        Mock Start-Process -ModuleName OfficeC2R { }
        $result = Set-OfficeC2RChannel -OfficeChannel Current -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$err" | Should -Match 'did not start'
    }

    It 'changes nothing under -WhatIf' {
        Set-OfficeC2RChannel -OfficeChannel Beta -WhatIf | Should -BeNullOrEmpty
        Should -Invoke Write-OfficeC2RConfigurationValue -ModuleName OfficeC2R -Times 0 -Exactly
        Should -Invoke Start-Process -ModuleName OfficeC2R -Times 0 -Exactly
    }
}

Describe 'GetOfficeVersion-Package.ps1 Import-OfficeC2RModule' {
    BeforeAll {
        Import-Module (Join-Path $repoRoot 'Tests/TestHelpers.psm1') -Force
        . (Get-ScriptFunctionDefinition -Path (Join-Path $repoRoot 'Scripts/Office/GetOfficeVersion-Package.ps1') -Name Import-OfficeC2RModule)
    }

    BeforeEach {
        Mock Import-Module { }
    }

    It 'imports the module folder bundled beside the script first' {
        $root = Join-Path $TestDrive 'pkg'
        $bundled = Join-Path (Join-Path $root 'OfficeC2R') 'OfficeC2R.psd1'
        $null = New-Item -ItemType File -Path $bundled -Force
        $null = New-Item -ItemType File -Path (Join-Path $TestDrive 'Modules/OfficeC2R/OfficeC2R.psd1') -Force
        Import-OfficeC2RModule -ScriptRoot $root
        Should -Invoke Import-Module -Times 1 -Exactly
        Should -Invoke Import-Module -Times 1 -Exactly -ParameterFilter { $Name -eq $bundled }
    }

    It 'imports the repository copy when nothing is bundled' {
        $root = Join-Path $TestDrive 'repo/Scripts/Office'
        $null = New-Item -ItemType Directory -Path $root -Force
        $null = New-Item -ItemType File -Path (Join-Path $TestDrive 'repo/Modules/OfficeC2R/OfficeC2R.psd1') -Force
        Import-OfficeC2RModule -ScriptRoot $root
        Should -Invoke Import-Module -Times 1 -Exactly -ParameterFilter { $Name -like '*Modules?OfficeC2R?OfficeC2R.psd1' }
    }

    It 'imports the module by name when no manifest is beside the script' {
        $root = Join-Path $TestDrive 'flat/Scripts/Office'
        $null = New-Item -ItemType Directory -Path $root -Force
        Import-OfficeC2RModule -ScriptRoot $root
        Should -Invoke Import-Module -Times 1 -Exactly -ParameterFilter { $Name -eq 'OfficeC2R' }
    }

    It 'throws one error naming every location tried when none works' {
        Mock Import-Module { throw 'no module named OfficeC2R' }
        $root = Join-Path $TestDrive 'empty/Scripts/Office'
        $null = New-Item -ItemType Directory -Path $root -Force
        $message = $null
        try { Import-OfficeC2RModule -ScriptRoot $root } catch { $message = "$_" }
        $message | Should -Match 'OfficeC2R module was not found'
        $message | Should -Match ([regex]::Escape((Join-Path (Join-Path $root 'OfficeC2R') 'OfficeC2R.psd1')))
        # The script joins this path with Join-Path, so Windows shows backslashes.
        $message | Should -Match 'Modules[\\/]OfficeC2R[\\/]OfficeC2R\.psd1'
        $message | Should -Match 'PSModulePath \(no module named OfficeC2R\)'
    }
}
