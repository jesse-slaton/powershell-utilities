#Requires -Version 5.1
# Behavior tests for Modules/PathRepair. The module is imported (it only defines functions);
# every environment read and write and every directory check is mocked, so these run on any
# OS and never touch the real PATH.

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'Modules/PathRepair/PathRepair.psd1') -Force
}

AfterAll {
    Remove-Module -Name PathRepair -Force -ErrorAction SilentlyContinue
}

Describe 'Get-MalformedPathEntry' {
    BeforeEach {
        # Only directories named C:\Good* exist.
        Mock Test-PathDirectory -ModuleName PathRepair { $Path.Trim('"') -like 'C:\Good*' }
    }

    It 'reports <Issue> for <Entry>' -ForEach @(
        @{ Path = 'C:\Good;C:\Good2"'; Entry = 'C:\Good2"'; Issue = 'Unbalanced double-quotes, suggest removal'; Suggested = 'C:\Good2' }
        @{ Path = 'C:\Good;C:\Missing'; Entry = 'C:\Missing'; Issue = 'Non-existent directory'; Suggested = 'Delete' }
        @{ Path = 'C:\Good; ;C:\Good2'; Entry = ' '; Issue = 'Non-existent directory'; Suggested = 'Delete' }
        @{ Path = 'C:\Good;c:\good'; Entry = 'c:\good'; Issue = 'Duplicate entry'; Suggested = 'Delete' }
        @{ Path = 'C:\Good;"C:\A;C:\B"'; Entry = '"C:\A;C:\B"'; Issue = 'Quoted span holds several entries, suggest removing the quotes'; Suggested = 'C:\A;C:\B' }
        @{ Path = 'C:\Good;"C:\A;"'; Entry = '"C:\A;"'; Issue = 'Quoted span holds several entries, suggest removing the quotes'; Suggested = 'C:\A' }
    ) {
        Mock Read-EnvironmentVariable -ModuleName PathRepair { $Path }
        $result = @(Get-MalformedPathEntry)
        $result.Count | Should -Be 1
        $result[0].Entry | Should -Be $Entry
        $result[0].Issue | Should -Be $Issue
        $result[0].SuggestedEntry | Should -Be $Suggested
    }

    It 'reads the process PATH, trims outer semicolons and never reports a bare drive root' {
        Mock Read-EnvironmentVariable -ModuleName PathRepair { ';C:\;C:\Good;' }
        Get-MalformedPathEntry | Should -BeNullOrEmpty
        Should -Invoke Read-EnvironmentVariable -ModuleName PathRepair -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'PATH' -and -not $PesterBoundParameters.ContainsKey('Target')
        }
    }

    It 'splits on semicolons next to a quoted entry, reporting only the missing one' -ForEach @(
        @{ Path = 'C:\Good;"C:\Good2";C:\Missing'; Count = 3 }
        @{ Path = '"C:\Good";"C:\Missing"'; Count = 2 }
        @{ Path = '"C:\Good;Q";C:\Missing'; Count = 2 }
    ) {
        Mock Read-EnvironmentVariable -ModuleName PathRepair { $Path }
        $result = @(Get-MalformedPathEntry)
        $result.Count | Should -Be 1
        $result[0].Entry | Should -Match '^"?C:\\Missing"?$'
        Should -Invoke Test-PathDirectory -ModuleName PathRepair -Times $Count -Exactly
    }

    It 'reports each entry between two stray quotes on its own, not as one glued entry' {
        Mock Read-EnvironmentVariable -ModuleName PathRepair { 'C:\Good;C:\Good1";C:\Good2;C:\Good3"' }
        $result = @(Get-MalformedPathEntry)
        $result.Count | Should -Be 2
        $result[0].Entry | Should -BeExactly 'C:\Good1"'
        $result[0].SuggestedEntry | Should -BeExactly 'C:\Good1'
        $result[1].Entry | Should -BeExactly 'C:\Good3"'
        $result[1].SuggestedEntry | Should -BeExactly 'C:\Good3'
    }

    It 'splits C:\;dir into the drive root and dir, so the drive-root semicolon check never matches' {
        Mock Read-EnvironmentVariable -ModuleName PathRepair { 'C:\;"C:\Good"' }
        Get-MalformedPathEntry | Should -BeNullOrEmpty
        Should -Invoke Test-PathDirectory -ModuleName PathRepair -Times 1 -Exactly -ParameterFilter { $Path -eq '"C:\Good"' }
    }

    It 'writes an error and outputs nothing when PATH is empty' {
        Mock Read-EnvironmentVariable -ModuleName PathRepair { $null }
        $result = Get-MalformedPathEntry -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$err" | Should -Match 'PATH environment variable is empty or not set'
    }

    It 'still answers to the Get-MalformedPathEntries alias' {
        Mock Read-EnvironmentVariable -ModuleName PathRepair { 'C:\Good;C:\Missing' }
        @(Get-MalformedPathEntries).Count | Should -Be 1
    }
}

Describe 'Restore-PathFromBackup' {
    BeforeEach {
        Mock Write-EnvironmentVariable -ModuleName PathRepair
        Mock Read-EnvironmentVariable -ModuleName PathRepair -ParameterFilter { $Name -eq 'BADPATH' } { 'C:\Old;C:\Older' }
        Mock Read-EnvironmentVariable -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH_FIX_DATE' } { '2026-01-01_10:00:00' }
        Mock Read-EnvironmentVariable -ModuleName PathRepair -ParameterFilter { $Name -eq 'BADPATH_SCOPE' } { 'User|2026-01-01_10:00:00' }
    }

    It 'writes BADPATH to the User PATH and deletes PATH_FIX_DATE, reading both from the User scope' {
        Restore-PathFromBackup
        Should -Invoke Write-EnvironmentVariable -ModuleName PathRepair -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'PATH' -and $Value -eq 'C:\Old;C:\Older' -and $Target -eq 'User'
        }
        Should -Invoke Write-EnvironmentVariable -ModuleName PathRepair -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'PATH_FIX_DATE' -and $null -eq $Value -and $Target -eq 'User'
        }
        Should -Invoke Read-EnvironmentVariable -ModuleName PathRepair -Times 3 -Exactly -ParameterFilter { $Target -eq 'User' }
    }

    It 'warns, and still restores, when BADPATH has no BADPATH_SCOPE=User marker' {
        Mock Read-EnvironmentVariable -ModuleName PathRepair -ParameterFilter { $Name -eq 'BADPATH_SCOPE' } { $null }
        Restore-PathFromBackup -WarningVariable warn -WarningAction SilentlyContinue
        "$warn" | Should -Match 'merged Machine and User PATH'
        Should -Invoke Write-EnvironmentVariable -ModuleName PathRepair -Times 1 -Exactly -ParameterFilter { $Name -eq 'PATH' }
    }

    It 'does not warn when BADPATH carries the marker for the current PATH_FIX_DATE' {
        Restore-PathFromBackup -WarningVariable warn -WarningAction SilentlyContinue
        $warn | Should -BeNullOrEmpty
    }

    It 'warns when the marker names an older PATH_FIX_DATE than the current one' {
        # A newer repair left the marker, then the old script rewrote BADPATH and PATH_FIX_DATE.
        Mock Read-EnvironmentVariable -ModuleName PathRepair -ParameterFilter { $Name -eq 'BADPATH_SCOPE' } { 'User|2025-12-31_09:00:00' }
        Restore-PathFromBackup -WarningVariable warn -WarningAction SilentlyContinue
        "$warn" | Should -Match 'merged Machine and User PATH'
    }

    It 'leaves PATH_FIX_DATE alone when it is not set, warning that the backup may be restored already' {
        Mock Read-EnvironmentVariable -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH_FIX_DATE' } { $null }
        Restore-PathFromBackup -WarningVariable warn -WarningAction SilentlyContinue
        "$warn" | Should -Match 'already restored'
        Should -Invoke Write-EnvironmentVariable -ModuleName PathRepair -Times 1 -Exactly
        Should -Invoke Write-EnvironmentVariable -ModuleName PathRepair -Times 1 -Exactly -ParameterFilter { $Name -eq 'PATH' }
    }

    It 'writes an error and changes nothing when BADPATH is not set' {
        Mock Read-EnvironmentVariable -ModuleName PathRepair -ParameterFilter { $Name -eq 'BADPATH' } { $null }
        Restore-PathFromBackup -ErrorVariable err -ErrorAction SilentlyContinue
        "$err" | Should -Match 'BADPATH environment variable does not exist'
        Should -Invoke Write-EnvironmentVariable -ModuleName PathRepair -Times 0 -Exactly
    }

    It 'changes nothing under -WhatIf' {
        Restore-PathFromBackup -WhatIf
        Should -Invoke Write-EnvironmentVariable -ModuleName PathRepair -Times 0 -Exactly
    }
}

Describe 'Private helpers' {
    It 'Test-PathDirectory is true only for an existing directory, quoted or not' {
        New-Item -Path (Join-Path $TestDrive 'dir[1]') -ItemType Directory | Out-Null
        Set-Content -Path (Join-Path $TestDrive 'file.txt') -Value 'x'
        InModuleScope PathRepair -Parameters @{ Root = $TestDrive } {
            param($Root)
            Test-PathDirectory -Path (Join-Path $Root 'dir[1]') | Should -BeTrue
            Test-PathDirectory -Path ('"{0}"' -f (Join-Path $Root 'dir[1]')) | Should -BeTrue
            Test-PathDirectory -Path (Join-Path $Root 'file.txt') | Should -BeFalse
            Test-PathDirectory -Path (Join-Path $Root 'missing') | Should -BeFalse
            Test-PathDirectory -Path ' ' | Should -BeFalse
            Test-PathDirectory -Path '""' | Should -BeFalse
        }
    }

    It 'Test-PathDirectory does not treat PowerShell drives as directories' {
        InModuleScope PathRepair {
            Test-PathDirectory -Path 'Env:' | Should -BeFalse
            Test-PathDirectory -Path 'Function:\' | Should -BeFalse
            Test-PathDirectory -Path 'Variable:\' | Should -BeFalse
        }
    }

    It 'Split-PathValue splits <Value> into <Expected>' -ForEach @(
        @{ Value = 'A;"B";C'; Expected = @('A', '"B"', 'C') }
        @{ Value = '"A";"B"'; Expected = @('"A"', '"B"') }
        @{ Value = '"A;B";C'; Expected = @('"A;B"', 'C') }
        @{ Value = 'A;;B'; Expected = @('A', '', 'B') }
        @{ Value = 'A";B;C'; Expected = @('A"', 'B', 'C') }
        @{ Value = 'A;B";C;D"'; Expected = @('A', 'B"', 'C', 'D"') }
        @{ Value = 'A";B;"C'; Expected = @('A"', 'B', '"C') }
        @{ Value = ''; Expected = @('') }
    ) {
        InModuleScope PathRepair -Parameters @{ Value = $Value; Expected = $Expected } {
            param($Value, $Expected)
            $result = @(Split-PathValue -Value $Value)
            $result.Count | Should -Be $Expected.Count
            for ($i = 0; $i -lt $Expected.Count; $i++) {
                $result[$i] | Should -BeExactly $Expected[$i]
            }
        }
    }

    It 'Read-EnvironmentVariable and Write-EnvironmentVariable round-trip a process variable' {
        InModuleScope PathRepair {
            $name = 'PATHREPAIR_TEST_{0}' -f [guid]::NewGuid().ToString('N')
            try {
                Write-EnvironmentVariable -Name $name -Value 'value' -Target Process
                Read-EnvironmentVariable -Name $name | Should -Be 'value'
                Write-EnvironmentVariable -Name $name -Value $null -Target Process
                Read-EnvironmentVariable -Name $name | Should -BeNullOrEmpty
            } finally {
                [System.Environment]::SetEnvironmentVariable($name, $null, 'Process')
            }
        }
    }
}

Describe 'Get-MalformedPathEntries-Sensor.ps1 wrapper' {
    It 'imports the PathRepair manifest by a path that exists in this repository' {
        # Parsed only, never run.
        $script = Join-Path $repoRoot 'Scripts/System/Get-MalformedPathEntries-Sensor.ps1'
        $text = Get-Content -Path $script -Raw
        $text -match "Join-Path \`$PSScriptRoot '(?<rel>[^']+)'" | Should -BeTrue
        $manifest = Join-Path (Split-Path -Parent $script) $Matches['rel']
        Test-Path -LiteralPath $manifest | Should -BeTrue
        $text | Should -Match 'Get-MalformedPathEntry \|'
    }

    It 'prints one sensor-error line and exits 1 when the module cannot be imported' {
        # Parsed only, never run: the import sits in a try whose catch writes the sentinel line.
        $script = Join-Path $repoRoot 'Scripts/System/Get-MalformedPathEntries-Sensor.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$null, [ref]$null)
        $try = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.TryStatementAst] }, $false))
        $try.Count | Should -Be 1
        $body = $try[0].Body.Extent.Text
        $body | Should -Match 'IsNullOrEmpty\(\$PSScriptRoot\)'
        $body | Should -Match 'Import-Module .* -ErrorAction Stop'
        $catch = $try[0].CatchClauses[0].Body.Extent.Text
        $catch | Should -Match "'PathRepair module not found\|Sensor error\|\{0\}' -f"
        $catch | Should -Match '(?m)^\s*exit 1\s*$'
    }
}
