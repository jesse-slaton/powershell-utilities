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

    It 'never reports a drive root in either case or in quotes, even when the drive is missing' {
        Mock Read-EnvironmentVariable -ModuleName PathRepair { 'c:\;D:\;"E:\";"f:\"' }
        Mock Test-PathDirectory -ModuleName PathRepair { $false }
        Get-MalformedPathEntry | Should -BeNullOrEmpty
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

    It 'does not join C:\ with an entry that holds a quote' {
        Mock Read-EnvironmentVariable -ModuleName PathRepair { 'C:\;"C:\Good"' }
        Get-MalformedPathEntry | Should -BeNullOrEmpty
        Should -Invoke Test-PathDirectory -ModuleName PathRepair -Times 1 -Exactly -ParameterFilter { $Path -eq '"C:\Good"' }
    }

    It 'reports a drive root and the relative entry after it as one split entry' {
        Mock Read-EnvironmentVariable -ModuleName PathRepair { 'C:\Good;C:\;Program Files\Foo;C:\Good2' }
        Mock Test-PathDirectory -ModuleName PathRepair { $Path -like 'C:\Good*' -or $Path -eq 'C:\Program Files\Foo' }
        $result = @(Get-MalformedPathEntry)
        $result.Count | Should -Be 1
        $result[0].Entry | Should -BeExactly 'C:\;Program Files\Foo'
        $result[0].Issue | Should -Be 'Incorrect semicolon after drive letter, suggest joining'
        $result[0].SuggestedEntry | Should -BeExactly 'C:\Program Files\Foo'
    }

    It 'does not report <Path> as a split entry' -ForEach @(
        @{ Path = 'C:\;D:\Tools' }
        @{ Path = 'C:\;\Tools' }
        @{ Path = 'C:\;%TOOLS%\bin' }
        @{ Path = 'C:\;.\Tools' }
        @{ Path = 'C:\; Tools' }
        @{ Path = 'C:\;Foo"' }
        @{ Path = 'C:\Good;Tools' }
        @{ Path = 'C:\;Nope' }
    ) {
        # Every path exists except C:\Nope, so only the text rules (or that one join) decide.
        Mock Read-EnvironmentVariable -ModuleName PathRepair { $Path }
        Mock Test-PathDirectory -ModuleName PathRepair { $Path -ne 'C:\Nope' }
        @(Get-MalformedPathEntry | Where-Object { $_.Issue -like 'Incorrect semicolon*' }) | Should -BeNullOrEmpty
    }

    It 'reports a split entry whose joined path repeats an earlier entry as a duplicate to delete' {
        Mock Read-EnvironmentVariable -ModuleName PathRepair { 'C:\Good;C:\;Good' }
        $result = @(Get-MalformedPathEntry)
        $result.Count | Should -Be 1
        $result[0].Entry | Should -BeExactly 'C:\;Good'
        $result[0].Issue | Should -Be 'Incorrect semicolon after drive letter, joined entry is a duplicate'
        $result[0].SuggestedEntry | Should -Be 'Delete'
    }

    It 'reports a later entry equal to a proposed join as a duplicate only once the join is applied' {
        Mock Read-EnvironmentVariable -ModuleName PathRepair { 'C:\;Tools;C:\Tools' }
        Mock Test-PathDirectory -ModuleName PathRepair { $true }
        $result = @(Get-MalformedPathEntry)
        $result.Count | Should -Be 2
        $result[0].SuggestedEntry | Should -BeExactly 'C:\Tools'
        $result[1].Entry | Should -BeExactly 'C:\Tools'
        $result[1].Issue | Should -Be "Duplicate of the joined entry 'C:\Tools' above, only once that join is applied"
        $result[1].SuggestedEntry | Should -Be 'Delete after joining'
        $result[1].SuggestedEntry | Should -Not -Be 'Delete'
    }

    It 'keeps the combined Delete when a join repeats an earlier real entry' {
        Mock Read-EnvironmentVariable -ModuleName PathRepair { 'C:\Tools;C:\;Tools' }
        Mock Test-PathDirectory -ModuleName PathRepair { $true }
        $result = @(Get-MalformedPathEntry)
        $result.Count | Should -Be 1
        $result[0].Issue | Should -Be 'Incorrect semicolon after drive letter, joined entry is a duplicate'
        $result[0].SuggestedEntry | Should -Be 'Delete'
    }

    It 'keeps a plain duplicate Delete for a repeat of a real entry' {
        Mock Read-EnvironmentVariable -ModuleName PathRepair { 'C:\Tools;C:\Tools' }
        Mock Test-PathDirectory -ModuleName PathRepair { $true }
        $result = @(Get-MalformedPathEntry)
        $result.Count | Should -Be 1
        $result[0].Issue | Should -Be 'Duplicate entry'
        $result[0].SuggestedEntry | Should -Be 'Delete'
    }

    It 'does not join a drive root and an entry holding a %VAR% Windows did not expand, reporting that entry instead' {
        $varName = 'PATHREPAIR_TEST_{0}' -f [guid]::NewGuid().ToString('N')
        [System.Environment]::SetEnvironmentVariable($varName, 'Good', 'Process')
        try {
            # Even a folder with the literal %VAR% name is not the one meant.
            Mock Read-EnvironmentVariable -ModuleName PathRepair { "C:\;Tools\%$varName%" }
            Mock Test-PathDirectory -ModuleName PathRepair { $true }
            $result = @(Get-MalformedPathEntry)
            $result.Count | Should -Be 1
            $result[0].Entry | Should -BeExactly "Tools\%$varName%"
            $result[0].Issue | Should -Be 'REG_SZ PATH: %VAR% is not expanded by Windows, suggest REG_EXPAND_SZ'
        } finally {
            [System.Environment]::SetEnvironmentVariable($varName, $null, 'Process')
        }
    }

    It 'reports a %VAR% entry left unexpanded in the process PATH (from a REG_SZ PATH), not one Windows expanded' {
        # Windows expands %VAR% only in REG_EXPAND_SZ, so the process PATH holds the expanded
        # form for one and the literal text for the other. Both folders exist only expanded.
        $varName = 'PATHREPAIR_TEST_{0}' -f [guid]::NewGuid().ToString('N')
        [System.Environment]::SetEnvironmentVariable($varName, 'C:\Good', 'Process')
        try {
            Mock Read-EnvironmentVariable -ModuleName PathRepair { "C:\Good\bin;%$varName%\tools" }
            Mock Test-PathDirectory -ModuleName PathRepair { $Path -in 'C:\Good\bin', 'C:\Good\tools' }
            $result = @(Get-MalformedPathEntry)
            $result.Count | Should -Be 1
            $result[0].Entry | Should -BeExactly "%$varName%\tools"
            $result[0].Issue | Should -Be 'REG_SZ PATH: %VAR% is not expanded by Windows, suggest REG_EXPAND_SZ'
            $result[0].SuggestedEntry | Should -BeExactly "%$varName%\tools"
            # Reported before, and without, the existence check.
            Should -Invoke Test-PathDirectory -ModuleName PathRepair -Times 0 -Exactly -ParameterFilter { $Path -eq "%$varName%\tools" }
        } finally {
            [System.Environment]::SetEnvironmentVariable($varName, $null, 'Process')
        }
    }

    It 'reports a later copy of an unexpanded %VAR% entry as a duplicate, the first copy as unexpanded' {
        $varName = 'PATHREPAIR_TEST_{0}' -f [guid]::NewGuid().ToString('N')
        [System.Environment]::SetEnvironmentVariable($varName, 'C:\Good', 'Process')
        try {
            Mock Read-EnvironmentVariable -ModuleName PathRepair { "%$varName%\tools;C:\Good;%$varName%\tools" }
            $result = @(Get-MalformedPathEntry)
            $result.Count | Should -Be 2
            $result[0].Issue | Should -Be 'REG_SZ PATH: %VAR% is not expanded by Windows, suggest REG_EXPAND_SZ'
            $result[0].SuggestedEntry | Should -BeExactly "%$varName%\tools"
            $result[1].Issue | Should -Be 'Duplicate entry'
            $result[1].SuggestedEntry | Should -Be 'Delete'
        } finally {
            [System.Environment]::SetEnvironmentVariable($varName, $null, 'Process')
        }
    }

    It 'reports an entry whose %VAR% is not set in this process as a missing directory' {
        $varName = 'PATHREPAIR_UNSET_{0}' -f [guid]::NewGuid().ToString('N')
        Mock Read-EnvironmentVariable -ModuleName PathRepair { "C:\Good;%$varName%\bin" }
        $result = @(Get-MalformedPathEntry)
        $result.Count | Should -Be 1
        $result[0].Issue | Should -Be 'Non-existent directory'
    }

    It 'agrees with the REG_SZ repair on a split drive root whose join holds an unset %VAR%' {
        # The variable is unset and a folder with the literal %VAR% name exists: neither
        # function joins the pair, and the %VAR% half is reported or kept as on its own.
        $varName = 'PATHREPAIR_UNSET_{0}' -f [guid]::NewGuid().ToString('N')
        $pathValue = "C:\;Tools\%$varName%"
        Mock Read-EnvironmentVariable -ModuleName PathRepair { $pathValue }
        Mock Read-UserEnvironmentValue -ModuleName PathRepair { [pscustomobject]@{ Value = $pathValue; Kind = 'String' } }
        Mock Test-PathDirectory -ModuleName PathRepair { $Path -eq "C:\Tools\%$varName%" }
        Mock Write-UserEnvironmentValue -ModuleName PathRepair
        Mock Send-EnvironmentChange -ModuleName PathRepair

        $report = @(Get-MalformedPathEntry)
        $report.Count | Should -Be 1
        $report[0].Entry | Should -BeExactly "Tools\%$varName%"
        $report[0].Issue | Should -Be 'Non-existent directory'

        $repair = Repair-PathEntry -Confirm:$false -WarningVariable warn -WarningAction SilentlyContinue
        @($repair.Changes).Count | Should -Be 0
        $repair.NewPath | Should -BeExactly $pathValue
        "$warn" | Should -Match ([regex]::Escape("'Tools\%$varName%' kept"))
        Should -Invoke Write-UserEnvironmentValue -ModuleName PathRepair -Times 0 -Exactly

        # The two agree: no split entry is reported, and no join is made.
        @($report | Where-Object { $_.Issue -like 'Incorrect semicolon*' }).Count | Should -Be 0
        @($repair.Changes | Where-Object { $_.Reason -like 'Incorrect semicolon*' }).Count | Should -Be 0
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

Describe 'Get-MalformedPathEntry, with real directory checks' {
    It 'reports an unexpanded %VAR% entry even when a directory with that literal name exists' {
        $varName = 'PATHREPAIR_TEST_{0}' -f [guid]::NewGuid().ToString('N')
        # Test-PathDirectory uses [System.IO.Directory]::Exists, which resolves a relative
        # path against the process working directory, not the PowerShell location, so the
        # entry is absolute: TestDrive\%VAR%\x, with that literal folder created.
        $entry = [System.IO.Path]::Combine($TestDrive, "%$varName%", 'x')
        New-Item -Path $entry -ItemType Directory -Force | Out-Null
        [System.Environment]::SetEnvironmentVariable($varName, (Join-Path $TestDrive 'expanded'), 'Process')
        Push-Location $TestDrive
        try {
            Mock Read-EnvironmentVariable -ModuleName PathRepair { "$TestDrive;$entry" }
            InModuleScope PathRepair -Parameters @{ Entry = $entry } { param($Entry) Test-PathDirectory -Path $Entry -Literal | Should -BeTrue }
            $result = @(Get-MalformedPathEntry)
            $result.Count | Should -Be 1
            $result[0].Entry | Should -BeExactly $entry
            $result[0].Issue | Should -Be 'REG_SZ PATH: %VAR% is not expanded by Windows, suggest REG_EXPAND_SZ'
            $result[0].SuggestedEntry | Should -BeExactly $entry
        } finally {
            Pop-Location
            [System.Environment]::SetEnvironmentVariable($varName, $null, 'Process')
        }
    }
}

Describe 'Repair-PathEntry, with real directory checks' {
    It 'warns about a kept %VAR% entry of a REG_SZ PATH even when a folder with that literal name exists' {
        $varName = 'PATHREPAIR_TEST_{0}' -f [guid]::NewGuid().ToString('N')
        # Absolute, as in the Get-MalformedPathEntry test above: TestDrive\%VAR%\x exists.
        $script:entry = [System.IO.Path]::Combine($TestDrive, "%$varName%", 'x')
        New-Item -Path $script:entry -ItemType Directory -Force | Out-Null
        [System.Environment]::SetEnvironmentVariable($varName, (Join-Path $TestDrive 'expanded'), 'Process')
        try {
            Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } {
                [pscustomobject]@{ Value = "$TestDrive;$script:entry"; Kind = 'String' }
            }
            Mock Write-UserEnvironmentValue -ModuleName PathRepair
            Mock Send-EnvironmentChange -ModuleName PathRepair
            InModuleScope PathRepair -Parameters @{ Entry = $script:entry } { param($Entry) Test-PathDirectory -Path $Entry -Literal | Should -BeTrue }
            $result = Repair-PathEntry -FixTypes NonExistentPaths -WhatIf -WarningVariable warn -WarningAction SilentlyContinue
            $result.NewPath | Should -BeExactly "$TestDrive;$script:entry"
            @($warn).Count | Should -Be 1
            "$warn" | Should -Match ([regex]::Escape("'$script:entry'"))
            "$warn" | Should -Match 'REG_SZ.*REG_EXPAND_SZ'
            "$warn" | Should -Not -Match 'does not exist'
        } finally {
            [System.Environment]::SetEnvironmentVariable($varName, $null, 'Process')
        }
    }
}

Describe 'Restore-PathFromBackup' {
    BeforeEach {
        Mock Write-UserEnvironmentValue -ModuleName PathRepair
        Mock Send-EnvironmentChange -ModuleName PathRepair
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'BADPATH' } { [pscustomobject]@{ Value = 'C:\Old;C:\Older'; Kind = 'String' } }
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH_FIX_DATE' } { [pscustomobject]@{ Value = '2026-01-01_10:00:00'; Kind = 'String' } }
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'BADPATH_SCOPE' } { [pscustomobject]@{ Value = 'User|2026-01-01_10:00:00'; Kind = 'String' } }
    }

    It 'writes BADPATH to the User PATH and deletes PATH_FIX_DATE, reading both from the User scope' {
        Restore-PathFromBackup
        Should -Invoke Write-UserEnvironmentValue -ModuleName PathRepair -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'PATH' -and $Value -eq 'C:\Old;C:\Older' -and $Kind -eq 'String'
        }
        Should -Invoke Write-UserEnvironmentValue -ModuleName PathRepair -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'PATH_FIX_DATE' -and [string]::IsNullOrEmpty($Value)
        }
        Should -Invoke Read-UserEnvironmentValue -ModuleName PathRepair -Times 3 -Exactly
        Should -Invoke Send-EnvironmentChange -ModuleName PathRepair -Times 1 -Exactly
    }

    It 'restores a REG_EXPAND_SZ backup with its %USERPROFILE% entry and kind unchanged' {
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'BADPATH' } {
            [pscustomobject]@{ Value = '%USERPROFILE%\bin;C:\Old'; Kind = 'ExpandString' }
        }
        Restore-PathFromBackup
        Should -Invoke Write-UserEnvironmentValue -ModuleName PathRepair -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'PATH' -and $Value -ceq '%USERPROFILE%\bin;C:\Old' -and $Kind -eq 'ExpandString'
        }
    }

    It 'warns, and still restores, when BADPATH has no BADPATH_SCOPE=User marker' {
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'BADPATH_SCOPE' } { [pscustomobject]@{ Value = $null; Kind = 'String' } }
        Restore-PathFromBackup -WarningVariable warn -WarningAction SilentlyContinue
        "$warn" | Should -Match 'merged Machine and User PATH'
        Should -Invoke Write-UserEnvironmentValue -ModuleName PathRepair -Times 1 -Exactly -ParameterFilter { $Name -eq 'PATH' }
    }

    It 'does not warn when BADPATH carries the marker for the current PATH_FIX_DATE' {
        Restore-PathFromBackup -WarningVariable warn -WarningAction SilentlyContinue
        $warn | Should -BeNullOrEmpty
    }

    It 'warns when the marker names an older PATH_FIX_DATE than the current one' {
        # A newer repair left the marker, then the old script rewrote BADPATH and PATH_FIX_DATE.
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'BADPATH_SCOPE' } { [pscustomobject]@{ Value = 'User|2025-12-31_09:00:00'; Kind = 'String' } }
        Restore-PathFromBackup -WarningVariable warn -WarningAction SilentlyContinue
        "$warn" | Should -Match 'merged Machine and User PATH'
    }

    It 'leaves PATH_FIX_DATE alone when it is not set, warning that the backup may be restored already' {
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH_FIX_DATE' } { [pscustomobject]@{ Value = $null; Kind = 'String' } }
        Restore-PathFromBackup -WarningVariable warn -WarningAction SilentlyContinue
        "$warn" | Should -Match 'already restored'
        Should -Invoke Write-UserEnvironmentValue -ModuleName PathRepair -Times 1 -Exactly
        Should -Invoke Write-UserEnvironmentValue -ModuleName PathRepair -Times 1 -Exactly -ParameterFilter { $Name -eq 'PATH' }
    }

    It 'writes an error and changes nothing when BADPATH is not set' {
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'BADPATH' } { [pscustomobject]@{ Value = $null; Kind = 'String' } }
        Restore-PathFromBackup -ErrorVariable err -ErrorAction SilentlyContinue
        "$err" | Should -Match 'BADPATH environment variable does not exist'
        Should -Invoke Write-UserEnvironmentValue -ModuleName PathRepair -Times 0 -Exactly
        Should -Invoke Send-EnvironmentChange -ModuleName PathRepair -Times 0 -Exactly
    }

    It 'changes nothing and broadcasts nothing under -WhatIf' {
        Restore-PathFromBackup -WhatIf
        Should -Invoke Write-UserEnvironmentValue -ModuleName PathRepair -Times 0 -Exactly
        Should -Invoke Send-EnvironmentChange -ModuleName PathRepair -Times 0 -Exactly
    }
}

Describe 'Repair-PathEntry' {
    BeforeEach {
        $script:writes = New-Object System.Collections.Generic.List[string]
        $script:kinds = @{}
        Mock Write-UserEnvironmentValue -ModuleName PathRepair { $script:writes.Add("User/$Name=$Value"); $script:kinds[$Name] = $Kind }
        Mock Send-EnvironmentChange -ModuleName PathRepair
        Mock Test-PathDirectory -ModuleName PathRepair { $Path.Trim('"') -like 'C:\Good*' }
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } {
            [pscustomobject]@{ Value = 'C:\Good;C:\Missing;c:\good;;C:\Good2"'; Kind = 'String' }
        }
    }

    It 'applies every fix type to the User PATH, writing BADPATH, its marker and PATH_FIX_DATE first' {
        $result = Repair-PathEntry -Confirm:$false
        $result.Applied | Should -BeTrue
        $result.OriginalPath | Should -Be 'C:\Good;C:\Missing;c:\good;;C:\Good2"'
        $result.NewPath | Should -Be 'C:\Good;C:\Good2'
        @($result.Changes | ForEach-Object { $_.Reason }) | Should -Be @(
            'Non-existent directory', 'Duplicate entry', 'Empty or blank entry', 'Unbalanced double-quotes')
        @($result.Changes)[3].NewEntry | Should -Be 'C:\Good2'
        $script:writes.Count | Should -Be 4
        $script:writes[0] | Should -Be 'User/BADPATH=C:\Good;C:\Missing;c:\good;;C:\Good2"'
        $script:writes[2] | Should -Match '^User/PATH_FIX_DATE=\d{4}-\d{2}-\d{2}_\d{2}:\d{2}:\d{2}$'
        $script:writes[1] | Should -BeExactly ('User/BADPATH_SCOPE=User|' + $script:writes[2].Substring('User/PATH_FIX_DATE='.Length))
        $script:writes[3] | Should -Be 'User/PATH=C:\Good;C:\Good2'
        Should -Invoke Read-UserEnvironmentValue -ModuleName PathRepair -Times 2 -Exactly
        Should -Invoke Send-EnvironmentChange -ModuleName PathRepair -Times 1 -Exactly
    }

    It 'keeps a %USERPROFILE% entry as written and the PATH value kind (<Kind>), in PATH and BADPATH' -ForEach @(
        @{ Kind = 'ExpandString' }
        @{ Kind = 'String' }
    ) {
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } {
            [pscustomobject]@{ Value = '%USERPROFILE%\bin;C:\Missing;%USERPROFILE%\bin'; Kind = $Kind }
        }
        Mock Test-PathDirectory -ModuleName PathRepair { $Path -ceq '%USERPROFILE%\bin' }
        $result = Repair-PathEntry -Confirm:$false
        $result.NewPath | Should -BeExactly '%USERPROFILE%\bin'
        $script:writes[0] | Should -BeExactly 'User/BADPATH=%USERPROFILE%\bin;C:\Missing;%USERPROFILE%\bin'
        $script:writes[3] | Should -BeExactly 'User/PATH=%USERPROFILE%\bin'
        $script:kinds['PATH'] | Should -BeExactly $Kind
        $script:kinds['BADPATH'] | Should -BeExactly $Kind
        $script:kinds['BADPATH_SCOPE'] | Should -BeExactly 'String'
        $script:kinds['PATH_FIX_DATE'] | Should -BeExactly 'String'
    }

    It 'checks a %VAR% entry as written in a <Kind> PATH (expanded folder exists: <Exists>), warning only for REG_SZ' -ForEach @(
        @{ Kind = 'ExpandString'; Exists = $true; Warnings = 0 }
        @{ Kind = 'ExpandString'; Exists = $false; Warnings = 0 }
        @{ Kind = 'String'; Exists = $true; Warnings = 1 }
        @{ Kind = 'String'; Exists = $false; Warnings = 1 }
    ) {
        # Windows expands %VAR% only in REG_EXPAND_SZ (checked on Windows 11 with
        # CreateEnvironmentBlock). The folder exists only expanded, and only when Exists is set.
        $varName = 'PATHREPAIR_TEST_{0}' -f [guid]::NewGuid().ToString('N')
        [System.Environment]::SetEnvironmentVariable($varName, 'C:\Users\me', 'Process')
        try {
            $script:entry = "%$varName%\bin"
            $script:exists = $Exists
            Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } {
                [pscustomobject]@{ Value = "C:\Good;$script:entry;C:\Missing"; Kind = $Kind }
            }
            Mock Test-PathDirectory -ModuleName PathRepair { $Path -eq 'C:\Good' -or ($script:exists -and -not $Literal -and $Path -eq $script:entry) }
            $result = Repair-PathEntry -FixTypes NonExistentPaths -Confirm:$false -WarningVariable warn -WarningAction SilentlyContinue
            $expected = if ($Kind -eq 'String' -or $Exists) { "C:\Good;$script:entry" } else { 'C:\Good' }
            $result.NewPath | Should -BeExactly $expected
            @($warn).Count | Should -Be $Warnings
            if ($Warnings) {
                "$warn" | Should -Match ([regex]::Escape("'$script:entry'"))
                "$warn" | Should -Match 'REG_SZ.*REG_EXPAND_SZ'
            }
            $script:kinds['PATH'] | Should -BeExactly $Kind
        } finally {
            [System.Environment]::SetEnvironmentVariable($varName, $null, 'Process')
        }
    }

    It 'compares duplicates as written: a %VAR%\bin entry and its expansion are both kept' {
        $varName = 'PATHREPAIR_TEST_{0}' -f [guid]::NewGuid().ToString('N')
        [System.Environment]::SetEnvironmentVariable($varName, 'C:\Users\me', 'Process')
        try {
            Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } {
                [pscustomobject]@{ Value = "%$varName%\bin;C:\Users\me\bin"; Kind = 'ExpandString' }
            }
            Mock Test-PathDirectory -ModuleName PathRepair { $true }
            @((Repair-PathEntry -FixTypes Duplicates -Confirm:$false).Changes).Count | Should -Be 0
        } finally {
            [System.Environment]::SetEnvironmentVariable($varName, $null, 'Process')
        }
    }

    It 'never removes as non-existent an entry whose %VAR% this process cannot expand' {
        $varName = 'PATHREPAIR_UNSET_{0}' -f [guid]::NewGuid().ToString('N')
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } {
            [pscustomobject]@{ Value = "C:\Good;%$varName%\bin;C:\Missing"; Kind = 'ExpandString' }
        }
        $result = Repair-PathEntry -FixTypes NonExistentPaths -Confirm:$false
        $result.NewPath | Should -BeExactly "C:\Good;%$varName%\bin"
    }

    It 'leaves a backup that Restore-PathFromBackup accepts without a warning' {
        $null = Repair-PathEntry -Confirm:$false
        $script:saved = @{}
        $script:writes | ForEach-Object { $n, $v = ($_ -replace '^User/', '') -split '=', 2; $script:saved[$n] = $v }
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -ne 'PATH' } { [pscustomobject]@{ Value = $script:saved[$Name]; Kind = $script:kinds[$Name] } }
        Restore-PathFromBackup -WarningVariable warn -WarningAction SilentlyContinue
        $warn | Should -BeNullOrEmpty
    }

    It 'fixes only the selected issue types' {
        $result = Repair-PathEntry -FixTypes Duplicates -Confirm:$false
        $result.NewPath | Should -Be 'C:\Good;C:\Missing;;C:\Good2"'
        $script:writes[3] | Should -Be 'User/PATH=C:\Good;C:\Missing;;C:\Good2"'
    }

    It 'keeps a quoted entry and its neighbours apart, removing only the missing one' {
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } { [pscustomobject]@{ Value = 'C:\Good;"C:\Good2";C:\Missing'; Kind = 'String' } }
        $result = Repair-PathEntry -Confirm:$false
        $result.NewPath | Should -Be 'C:\Good;"C:\Good2"'
        $script:writes[3] | Should -Be 'User/PATH=C:\Good;"C:\Good2"'
    }

    It 'keeps every existing entry between or inside stray quotes and an existing quoted C:\P;Q' {
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } { [pscustomobject]@{ Value = 'C:\Keep;C:\A\bin";C:\Windows;C:\B\bin";"C:\X;C:\Y";"C:\P;Q"'; Kind = 'String' } }
        Mock Test-PathDirectory -ModuleName PathRepair { @('C:\Keep', 'C:\A\bin', 'C:\Windows', 'C:\B\bin', 'C:\X', 'C:\Y', 'C:\P;Q') -contains $Path.Trim('"') }
        $result = Repair-PathEntry -Confirm:$false
        $result.NewPath | Should -BeExactly 'C:\Keep;C:\A\bin;C:\Windows;C:\B\bin;C:\X;C:\Y;"C:\P;Q"'
        $script:writes[3] | Should -BeExactly 'User/PATH=C:\Keep;C:\A\bin;C:\Windows;C:\B\bin;C:\X;C:\Y;"C:\P;Q"'
    }

    It 'unquotes, never removes, two stray quotes around existing entries in <PathValue>' -ForEach @(
        @{ PathValue = 'C:\Keep;"C:\A\bin;C:\Windows;C:\B\bin"'; Expected = 'C:\Keep;C:\A\bin;C:\Windows;C:\B\bin' }
        @{ PathValue = 'C:\Keep;"C:\A\bin;C:\Windows";C:\B'; Expected = 'C:\Keep;C:\A\bin;C:\Windows;C:\B' }
    ) {
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } { [pscustomobject]@{ Value = $PathValue; Kind = 'String' } }
        Mock Test-PathDirectory -ModuleName PathRepair { @('C:\Keep', 'C:\A\bin', 'C:\Windows', 'C:\B\bin', 'C:\B') -contains $Path.Trim('"') }
        $result = Repair-PathEntry -Confirm:$false
        $result.NewPath | Should -BeExactly $Expected
        @($result.Changes).Count | Should -Be 1
        @($result.Changes)[0].Reason | Should -Be 'Quoted span holds several entries'
        $script:writes[3] | Should -BeExactly "User/PATH=$Expected"
        # The written PATH splits back into the separate entries, so a second run changes nothing.
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } { [pscustomobject]@{ Value = $Expected; Kind = 'String' } }
        @((Repair-PathEntry -Confirm:$false).Changes).Count | Should -Be 0
        $script:writes.Count | Should -Be 4
    }

    It 'keeps unchanged an existing quoted directory whose name holds a semicolon' {
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } { [pscustomobject]@{ Value = 'C:\Good;"C:\Good;Q"'; Kind = 'String' } }
        $result = Repair-PathEntry -Confirm:$false
        $result.Applied | Should -BeFalse
        @($result.Changes).Count | Should -Be 0
        Should -Invoke Write-UserEnvironmentValue -ModuleName PathRepair -Times 0 -Exactly
    }

    It 'changes nothing under -WhatIf and returns the proposed repair' {
        $result = Repair-PathEntry -WhatIf
        $result.Applied | Should -BeFalse
        $result.NewPath | Should -Be 'C:\Good;C:\Good2'
        @($result.Changes).Count | Should -Be 4
        Should -Invoke Write-UserEnvironmentValue -ModuleName PathRepair -Times 0 -Exactly
        Should -Invoke Send-EnvironmentChange -ModuleName PathRepair -Times 0 -Exactly
    }

    It 'changes nothing when no entry needs fixing' {
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } { [pscustomobject]@{ Value = 'C:\Good;C:\'; Kind = 'String' } }
        $result = Repair-PathEntry -Confirm:$false
        $result.Applied | Should -BeFalse
        @($result.Changes).Count | Should -Be 0
        Should -Invoke Write-UserEnvironmentValue -ModuleName PathRepair -Times 0 -Exactly
        Should -Invoke Send-EnvironmentChange -ModuleName PathRepair -Times 0 -Exactly
    }

    It 'IncorrectSemicolons does not join C:\ with an entry that holds a quote' {
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } { [pscustomobject]@{ Value = 'C:\;"Good"\'; Kind = 'String' } }
        $result = Repair-PathEntry -FixTypes IncorrectSemicolons -Confirm:$false
        @($result.Changes).Count | Should -Be 0
        Should -Invoke Write-UserEnvironmentValue -ModuleName PathRepair -Times 0 -Exactly
    }

    It 'IncorrectSemicolons joins a drive root and the relative entry after it into one entry' {
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } {
            [pscustomobject]@{ Value = 'C:\Good;C:\;Program Files\Foo;C:\Missing'; Kind = 'String' }
        }
        Mock Test-PathDirectory -ModuleName PathRepair { $Path -like 'C:\Good*' -or $Path -eq 'C:\Program Files\Foo' }
        $result = Repair-PathEntry -Confirm:$false
        $result.NewPath | Should -BeExactly 'C:\Good;C:\Program Files\Foo'
        $change = @($result.Changes)[0]
        $change.Entry | Should -BeExactly 'C:\;Program Files\Foo'
        $change.NewEntry | Should -BeExactly 'C:\Program Files\Foo'
        $change.Reason | Should -Be 'Incorrect semicolon after drive letter'
        $script:writes[3] | Should -BeExactly 'User/PATH=C:\Good;C:\Program Files\Foo'
    }

    It 'IncorrectSemicolons changes nothing for <PathValue>' -ForEach @(
        @{ PathValue = 'C:\Good;C:\;D:\Tools' }
        @{ PathValue = 'C:\Good;C:\;"Good"\' }
        @{ PathValue = 'C:\Good;C:\;\Tools' }
        @{ PathValue = 'C:\Good;C:\;%TOOLS%\bin' }
        @{ PathValue = 'C:\Good;C:\; Tools' }
        @{ PathValue = 'C:\Good;C:\;Foo"' }
        @{ PathValue = 'C:\Good;C:\;Nope' }
    ) {
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } { [pscustomobject]@{ Value = $PathValue; Kind = 'String' } }
        Mock Test-PathDirectory -ModuleName PathRepair { $Path -ne 'C:\Nope' }
        $result = Repair-PathEntry -FixTypes IncorrectSemicolons -Confirm:$false
        @($result.Changes).Count | Should -Be 0
        Should -Invoke Write-UserEnvironmentValue -ModuleName PathRepair -Times 0 -Exactly
    }

    It 'never joins a drive root and an entry holding a stray quote, leaving the quote to UnbalancedQuotes' {
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } { [pscustomobject]@{ Value = 'C:\Good;C:\;Foo"'; Kind = 'String' } }
        Mock Test-PathDirectory -ModuleName PathRepair { $Path.Trim('"') -like 'C:\Good*' -or $Path.Trim('"') -eq 'C:\Foo' }
        $result = Repair-PathEntry -Confirm:$false
        @($result.Changes | Where-Object { $_.Reason -like 'Incorrect semicolon*' }) | Should -BeNullOrEmpty
        $result.NewPath | Should -Not -Match '"'
        $script:writes[3] | Should -BeExactly 'User/PATH=C:\Good;C:\'
    }

    It 'joins a pair that repeats an earlier entry, then removes it as a duplicate, two changes' {
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } { [pscustomobject]@{ Value = 'C:\Tools;C:\;Tools;C:\Good'; Kind = 'String' } }
        Mock Test-PathDirectory -ModuleName PathRepair { $Path -in 'C:\Tools', 'C:\Good' }
        $result = Repair-PathEntry -Confirm:$false
        $result.NewPath | Should -BeExactly 'C:\Tools;C:\Good'
        @($result.Changes).Count | Should -Be 2
        @($result.Changes)[0].Entry | Should -BeExactly 'C:\;Tools'
        @($result.Changes)[0].NewEntry | Should -BeExactly 'C:\Tools'
        @($result.Changes)[0].Reason | Should -Be 'Incorrect semicolon after drive letter'
        @($result.Changes)[1].Entry | Should -BeExactly 'C:\Tools'
        @($result.Changes)[1].NewEntry | Should -BeNullOrEmpty
        @($result.Changes)[1].Reason | Should -Be 'Duplicate entry'
        $script:writes[0] | Should -BeExactly 'User/BADPATH=C:\Tools;C:\;Tools;C:\Good'
        $script:writes[3] | Should -BeExactly 'User/PATH=C:\Tools;C:\Good'
    }

    It 'under -WhatIf lists every join as approved and the other changes of the joined PATH, writing nothing' {
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } { [pscustomobject]@{ Value = 'C:\Tools;C:\;Tools;C:\Good'; Kind = 'String' } }
        Mock Test-PathDirectory -ModuleName PathRepair { $Path -in 'C:\Tools', 'C:\Good' }
        $result = Repair-PathEntry -WhatIf
        $result.Applied | Should -BeFalse
        $result.OriginalPath | Should -BeExactly 'C:\Tools;C:\;Tools;C:\Good'
        $result.NewPath | Should -BeExactly 'C:\Tools;C:\Good'
        @($result.Changes | ForEach-Object { "$($_.Entry)>$($_.NewEntry)" }) | Should -Be @('C:\;Tools>C:\Tools', 'C:\Tools>')
        Should -Invoke Write-UserEnvironmentValue -ModuleName PathRepair -Times 0 -Exactly
    }

    It 'shows the warnings of the joined PATH once, and not those of the PATH as read as well' {
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } { [pscustomobject]@{ Value = 'C:\;Tools;C:\Bin\%PSU_NOT_EXPANDED%'; Kind = 'String' } }
        Mock Test-PathDirectory -ModuleName PathRepair { $Path -eq 'C:\Tools' }
        # 3>&1 collects the warnings shown; -WarningVariable would also hold the held-back ones.
        $output = @(Repair-PathEntry -Confirm:$false 3>&1)
        $warnings = @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $warnings.Count | Should -Be 1
        "$($warnings[0])" | Should -BeLike "*'C:\Bin\%PSU_NOT_EXPANDED%' kept*"
        $script:writes[3] | Should -BeExactly 'User/PATH=C:\Tools;C:\Bin\%PSU_NOT_EXPANDED%'
    }

    It 'IncorrectSemicolons alone joins a pair that repeats an earlier entry, leaving the copy to Duplicates' {
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } { [pscustomobject]@{ Value = 'C:\Tools;C:\;Tools'; Kind = 'String' } }
        Mock Test-PathDirectory -ModuleName PathRepair { $Path -eq 'C:\Tools' }
        $result = Repair-PathEntry -FixTypes IncorrectSemicolons -Confirm:$false
        $result.NewPath | Should -BeExactly 'C:\Tools;C:\Tools'
        @($result.Changes).Count | Should -Be 1
        @($result.Changes)[0].Entry | Should -BeExactly 'C:\;Tools'
        @($result.Changes)[0].NewEntry | Should -BeExactly 'C:\Tools'
        @($result.Changes)[0].Reason | Should -Be 'Incorrect semicolon after drive letter'
        $script:writes[3] | Should -BeExactly 'User/PATH=C:\Tools;C:\Tools'
    }

    It 'reports a completed write as applied, with one warning, when the broadcast internals fail' {
        # A child process, so the broadcast type is not loaded yet and Add-Type runs (and
        # throws); off Windows the platform check throws instead. The real PATH is never touched.
        $childScript = Join-Path $TestDrive 'broadcast-fails.ps1'
        Set-Content -Path $childScript -Value @'
param($Manifest)
Import-Module $Manifest -Force -ErrorAction Stop
& (Get-Module PathRepair) {
    $script:store = @{ PATH = 'C:\Good;C:\Missing' }
    function script:Read-UserEnvironmentValue { param($Name) [pscustomobject]@{ Value = $script:store[$Name]; Kind = 'ExpandString' } }
    function script:Write-UserEnvironmentValue { param($Name, $Value, $Kind) $script:store[$Name] = $Value }
    function script:Test-PathDirectory { param($Path, [switch]$Literal) $Path -eq 'C:\Good' }
    function script:Add-Type { throw 'Add-Type failed (simulated)' }
}
# 2>&1 collects what reaches the error stream (-ErrorVariable would also hold the caught throw).
$all = @(Repair-PathEntry -FixTypes NonExistentPaths -Confirm:$false -WarningVariable warn -WarningAction SilentlyContinue 2>&1)
$err = @($all | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
$result = $all | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | Select-Object -First 1
$path = & (Get-Module PathRepair) { $script:store['PATH'] }
try {
    Restore-PathFromBackup -Confirm:$false -ErrorAction Stop -WarningVariable restoreWarn -WarningAction SilentlyContinue
    $restoreError = ''
} catch {
    $restoreError = "$_"
}
[pscustomobject]@{
    Applied = $result.Applied; NewPath = $result.NewPath; Errors = @($err).Count; Warnings = @($warn).Count; Warning = "$warn"
    Written = $path; Restored = (& (Get-Module PathRepair) { $script:store['PATH'] }); RestoreError = $restoreError
    RestoreWarnings = @($restoreWarn).Count
} | ConvertTo-Json -Compress
'@
        $manifest = Join-Path $repoRoot 'Modules/PathRepair/PathRepair.psd1'
        $powershell = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $output = @(& $powershell -NoProfile -NonInteractive -File $childScript -Manifest $manifest)
        $child = $output[-1] | ConvertFrom-Json
        $child.Applied | Should -BeTrue
        $child.NewPath | Should -BeExactly 'C:\Good'
        $child.Written | Should -BeExactly 'C:\Good'
        $child.Errors | Should -Be 0
        $child.Warnings | Should -Be 1
        $child.Warning | Should -Match 'not told about the new environment'
        $child.RestoreError | Should -BeNullOrEmpty
        $child.Restored | Should -BeExactly 'C:\Good;C:\Missing'
        $child.RestoreWarnings | Should -Be 1
    }

    It 'writes nothing when the User PATH changed between the preview and the write' {
        $script:reads = 0
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } {
            $script:reads++
            $value = if ($script:reads -eq 1) { 'C:\Good;C:\Missing' } else { 'C:\Good;C:\Missing;C:\JustInstalled' }
            [pscustomobject]@{ Value = $value; Kind = 'String' }
        }
        $result = Repair-PathEntry -FixTypes NonExistentPaths -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$err" | Should -Match 'User PATH changed since the preview; nothing written'
        Should -Invoke Write-UserEnvironmentValue -ModuleName PathRepair -Times 0 -Exactly
    }

    It 'writes nothing when the User PATH value kind changed from <From> to <To> with the same text' -ForEach @(
        @{ From = 'String'; To = 'ExpandString' }
        @{ From = 'ExpandString'; To = 'String' }
    ) {
        $script:reads = 0
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } {
            $script:reads++
            $kind = if ($script:reads -eq 1) { $From } else { $To }
            [pscustomobject]@{ Value = 'C:\Good;%USERPROFILE%\bin;C:\Missing'; Kind = $kind }
        }
        $result = Repair-PathEntry -FixTypes NonExistentPaths -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        $script:reads | Should -Be 2
        "$err" | Should -Match "User PATH changed since the preview \(its value kind is now $To, not $From\); nothing written"
        # Not BADPATH, BADPATH_SCOPE, PATH_FIX_DATE or PATH.
        $script:writes | Should -BeNullOrEmpty
        Should -Invoke Write-UserEnvironmentValue -ModuleName PathRepair -Times 0 -Exactly
        Should -Invoke Send-EnvironmentChange -ModuleName PathRepair -Times 0 -Exactly
    }

    It 'never removes a drive root in either case or in quotes, even when the drive is missing' {
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } { [pscustomobject]@{ Value = 'C:\Keep;c:\;D:\;"E:\";"f:\"'; Kind = 'String' } }
        Mock Test-PathDirectory -ModuleName PathRepair { $Path -eq 'C:\Keep' }
        $result = Repair-PathEntry -FixTypes NonExistentPaths -Confirm:$false
        @($result.Changes) | Should -BeNullOrEmpty
        $result.NewPath | Should -BeExactly $result.OriginalPath
        $result.Applied | Should -BeFalse
        Should -Invoke Write-UserEnvironmentValue -ModuleName PathRepair -Times 0 -Exactly
    }

    It 'keeps leading and trailing empty entries when neither BlankEntries nor NonExistentPaths is selected' {
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } { [pscustomobject]@{ Value = ';C:\Good;C:\Good;'; Kind = 'String' } }
        $result = Repair-PathEntry -FixTypes Duplicates -Confirm:$false
        $result.NewPath | Should -BeExactly ';C:\Good;'
        @($result.Changes).Count | Should -Be 1
        $script:writes[3] | Should -BeExactly 'User/PATH=;C:\Good;'
    }

    It 'never removes a blank entry as a duplicate of another blank' {
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } { [pscustomobject]@{ Value = 'C:\Good;;C:\Other;;C:\Good'; Kind = 'String' } }
        $result = Repair-PathEntry -FixTypes Duplicates -Confirm:$false
        $result.NewPath | Should -BeExactly 'C:\Good;;C:\Other;'
        @($result.Changes).Count | Should -Be 1
    }

    It 'removes leading and trailing empty entries as approved BlankEntries changes' {
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } { [pscustomobject]@{ Value = ';C:\Good;'; Kind = 'String' } }
        Mock Test-PathDirectory -ModuleName PathRepair { $Path -eq 'C:\Good' }
        $result = Repair-PathEntry -FixTypes BlankEntries -Confirm:$false
        $result.NewPath | Should -BeExactly 'C:\Good'
        @($result.Changes | Where-Object { $_.Reason -eq 'Empty or blank entry' }).Count | Should -Be 2
    }

    It 'drops duplicate parts of an unquoted span: <Path>' -ForEach @(
        @{ Path = '"C:\A;C:\A";C:\B'; NewPath = 'C:\A;C:\B'; Reasons = 'Quoted span holds several entries, duplicates dropped' }
        @{ Path = 'C:\A;"C:\A;C:\B"'; NewPath = 'C:\A;C:\B'; Reasons = 'Quoted span holds several entries, duplicates dropped' }
        @{ Path = '"C:\A;C:\B";C:\A'; NewPath = 'C:\A;C:\B'; Reasons = 'Quoted span holds several entries|Duplicate entry' }
        @{ Path = 'C:\A;"C:\A;C:\A";C:\B'; NewPath = 'C:\A;C:\B'; Reasons = 'Quoted span holds only duplicate entries' }
        @{ Path = '"C:\A;C:\B";"C:\A;C:\B"'; NewPath = 'C:\A;C:\B'; Reasons = 'Quoted span holds several entries|Quoted span holds only duplicate entries' }
        @{ Path = '"C:\A;C:\B";"C:\B;C:\C"'; NewPath = 'C:\A;C:\B;C:\C'; Reasons = 'Quoted span holds several entries|Quoted span holds several entries, duplicates dropped' }
    ) {
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } { [pscustomobject]@{ Value = $Path; Kind = 'String' } }
        Mock Test-PathDirectory -ModuleName PathRepair { @('C:\A', 'C:\B', 'C:\C') -contains $Path }
        $result = Repair-PathEntry -Confirm:$false
        $result.NewPath | Should -BeExactly $NewPath
        @($result.Changes | ForEach-Object { $_.Reason }) -join '|' | Should -Be $Reasons
    }

    It 'writes nothing when the repair would leave the User PATH empty' {
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } { [pscustomobject]@{ Value = '\\server\share;Z:\Mapped'; Kind = 'String' } }
        $result = Repair-PathEntry -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$err" | Should -Match 'would remove every User PATH entry; nothing written'
        Should -Invoke Write-UserEnvironmentValue -ModuleName PathRepair -Times 0 -Exactly
    }

    It 'writes an error and changes nothing when the User PATH is empty' {
        Mock Read-UserEnvironmentValue -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } { [pscustomobject]@{ Value = ''; Kind = 'String' } }
        $result = Repair-PathEntry -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$err" | Should -Match 'User PATH on this computer: The User PATH environment variable is empty'
        Should -Invoke Write-UserEnvironmentValue -ModuleName PathRepair -Times 0 -Exactly
    }

    It 'still answers to the Repair-PathEntries alias' {
        (Repair-PathEntries -WhatIf).NewPath | Should -Be 'C:\Good;C:\Good2'
    }

    It 'asks before each change with -Prompt' {
        # A runspace with no host UI fails any ShouldProcess prompt, which proves one was attempted.
        $manifest = Join-Path $repoRoot 'Modules/PathRepair/PathRepair.psd1'
        $run = {
            param($Manifest, [bool]$Prompt)
            Import-Module $Manifest -Force -ErrorAction Stop
            & (Get-Module PathRepair) {
                function script:Read-UserEnvironmentValue { param($Name) [pscustomobject]@{ Value = 'C:\Good;C:\Missing'; Kind = 'String' } }
                function script:Write-UserEnvironmentValue { param($Name, $Value, $Kind) }
                function script:Send-EnvironmentChange { }
                function script:Test-PathDirectory { param($Path) $Path -eq 'C:\Good' }
            }
            try {
                $null = Repair-PathEntry -FixTypes NonExistentPaths -Prompt:$Prompt -ErrorAction Stop
                'NO-PROMPT'
            } catch {
                "PROMPTED: $($_.Exception.Message)"
            }
        }
        foreach ($case in @(@{ Prompt = $true; Expected = '^PROMPTED: .*(prompt|interact)' }, @{ Prompt = $false; Expected = '^NO-PROMPT$' })) {
            $ps = [powershell]::Create()
            try {
                $output = @($ps.AddScript("$run").AddArgument($manifest).AddArgument($case.Prompt).Invoke())
                $output[-1] | Should -Match $case.Expected
            } finally {
                $ps.Dispose()
            }
        }
    }
}

Describe 'Select-ApprovedPathChange' {
    BeforeAll {
        function New-FakeCmdlet ([bool[]]$Answers) {
            $fake = [pscustomobject]@{ Answers = $Answers; Calls = New-Object System.Collections.Generic.List[string] }
            $fake | Add-Member -MemberType ScriptMethod -Name ShouldProcess -Value {
                param($Target, $Action)
                $this.Calls.Add("$Target|$Action")
                $this.Answers[$this.Calls.Count - 1]
            }
            $fake
        }
    }

    It 'applies only the approved changes and keeps every declined entry as it was' {
        $plan = [pscustomobject]@{
            Entries = @('C:\Good', 'C:\Missing', 'C:\Gone', 'C:\Good2"')
            Changes = @(
                [pscustomobject]@{ Index = 1; Entry = 'C:\Missing'; NewEntry = $null; Reason = 'Non-existent directory' }
                [pscustomobject]@{ Index = 2; Entry = 'C:\Gone'; NewEntry = $null; Reason = 'Non-existent directory' }
                [pscustomobject]@{ Index = 3; Entry = 'C:\Good2"'; NewEntry = 'C:\Good2'; Reason = 'Unbalanced double-quotes' }
            )
        }
        $fake = New-FakeCmdlet -Answers $false, $true, $true
        $result = InModuleScope PathRepair -Parameters @{ Fake = $fake; Plan = $plan } {
            param($Fake, $Plan)
            Select-ApprovedPathChange -Cmdlet $Fake -Target 'User PATH on this computer' -Plan $Plan
        }
        $result.NewPath | Should -Be 'C:\Good;C:\Missing;C:\Good2'
        @($result.Changes | ForEach-Object { $_.Index }) | Should -Be @(2, 3)
        $fake.Calls | Should -Be @(
            "User PATH on this computer|Remove entry 'C:\Missing' (Non-existent directory)"
            "User PATH on this computer|Remove entry 'C:\Gone' (Non-existent directory)"
            "User PATH on this computer|Replace entry 'C:\Good2`"' with 'C:\Good2' (Unbalanced double-quotes)"
        )
    }

    It 'skips, without asking, a duplicate removal whose original kept its declined fix' -ForEach @(
        @{ Answers = @($false); WhatIf = $false; Calls = 1; NewPath = 'C:\A";C:\A;C:\Win' }
        @{ Answers = @($true, $true); WhatIf = $false; Calls = 2; NewPath = 'C:\A;C:\Win' }
        @{ Answers = @($false, $false); WhatIf = $true; Calls = 2; NewPath = 'C:\A";C:\A;C:\Win' }
    ) {
        $fake = New-FakeCmdlet -Answers $Answers
        $result = InModuleScope PathRepair -Parameters @{ Fake = $fake; WhatIf = $WhatIf } {
            param($Fake, $WhatIf)
            Mock Read-UserEnvironmentValue { [pscustomobject]@{ Value = 'C:\A";C:\A;C:\Win'; Kind = 'String' } }
            Mock Test-PathDirectory { @('C:\A', 'C:\Win') -contains $Path }
            $plan = Invoke-PathRepairCore -FixTypes UnbalancedQuotes, Duplicates, NonExistentPaths
            @($plan.Changes)[1].DuplicateOf | Should -Be 0
            $WhatIfPreference = $WhatIf
            Select-ApprovedPathChange -Cmdlet $Fake -Target 'User PATH' -Plan $plan
        }
        $fake.Calls.Count | Should -Be $Calls
        $result.NewPath | Should -BeExactly $NewPath
    }

    It 'keeps a later copy of a span part, without asking, when the span is declined' -ForEach @(
        @{ Answers = @($false); Calls = 1; NewPath = '"C:\A;C:\B";C:\A' }
        @{ Answers = @($true, $true); Calls = 2; NewPath = 'C:\A;C:\B' }
    ) {
        $fake = New-FakeCmdlet -Answers $Answers
        $result = InModuleScope PathRepair -Parameters @{ Fake = $fake } {
            param($Fake)
            Mock Read-UserEnvironmentValue { [pscustomobject]@{ Value = '"C:\A;C:\B";C:\A'; Kind = 'String' } }
            Mock Test-PathDirectory { @('C:\A', 'C:\B') -contains $Path }
            $plan = Invoke-PathRepairCore -FixTypes Duplicates, NonExistentPaths
            @($plan.Changes)[1].DuplicateOf | Should -Be 0
            Select-ApprovedPathChange -Cmdlet $Fake -Target 'User PATH' -Plan $plan
        }
        $fake.Calls.Count | Should -Be $Calls
        $result.NewPath | Should -BeExactly $NewPath
    }

    It 'keeps the parts a declined span would have supplied when a later span repeats them: <Path>' -ForEach @(
        @{ Path = '"C:\A;C:\B";"C:\A;C:\B"'; Answers = @($false, $true); NewPath = '"C:\A;C:\B";C:\A;C:\B'; Written = 'C:\A;C:\B'
            Second = "Replace entry '`"C:\A;C:\B`"' with 'C:\A;C:\B' (Quoted span holds several entries)" }
        @{ Path = '"C:\A;C:\B";"C:\B;C:\C"'; Answers = @($false, $true); NewPath = '"C:\A;C:\B";C:\B;C:\C'; Written = 'C:\B;C:\C'
            Second = "Replace entry '`"C:\B;C:\C`"' with 'C:\B;C:\C' (Quoted span holds several entries)" }
        @{ Path = '"C:\A;C:\B";"C:\B;C:\C"'; Answers = @($true, $true); NewPath = 'C:\A;C:\B;C:\C'; Written = 'C:\A;C:\B|C:\C'
            Second = "Replace entry '`"C:\B;C:\C`"' with 'C:\C' (Quoted span holds several entries, duplicates dropped)" }
    ) {
        $fake = New-FakeCmdlet -Answers $Answers
        $result = InModuleScope PathRepair -Parameters @{ Fake = $fake; Path = $Path } {
            param($Fake, $Path)
            Mock Read-UserEnvironmentValue { [pscustomobject]@{ Value = $Path; Kind = 'String' } }
            Mock Test-PathDirectory { @('C:\A', 'C:\B', 'C:\C') -contains $Path }
            $plan = Invoke-PathRepairCore -FixTypes Duplicates, NonExistentPaths
            Select-ApprovedPathChange -Cmdlet $Fake -Target 'User PATH' -Plan $plan
        }
        $fake.Calls.Count | Should -Be 2
        $fake.Calls[1] | Should -BeExactly "User PATH|$Second"
        $result.NewPath | Should -BeExactly $NewPath        # The reported changes are the ones written, fallback included.
        @($result.Changes | ForEach-Object { if ($null -eq $_.NewEntry) { '-' } else { $_.NewEntry } }) -join '|' | Should -BeExactly $Written
    }

    It 'decides two entries with the same text separately' {
        $plan = [pscustomobject]@{
            Entries = @('C:\Missing', 'C:\Missing')
            Changes = @(
                [pscustomobject]@{ Index = 0; Entry = 'C:\Missing'; NewEntry = $null; Reason = 'Non-existent directory' }
                [pscustomobject]@{ Index = 1; Entry = 'C:\Missing'; NewEntry = $null; Reason = 'Non-existent directory' }
            )
        }
        $result = InModuleScope PathRepair -Parameters @{ Fake = (New-FakeCmdlet -Answers $false, $true); Plan = $plan } {
            param($Fake, $Plan)
            Select-ApprovedPathChange -Cmdlet $Fake -Target 'User PATH' -Plan $Plan
        }
        $result.NewPath | Should -Be 'C:\Missing'
        @($result.Changes).Count | Should -Be 1
    }
}

Describe 'Select-ApprovedPathRepair' {
    BeforeDiscovery {
        $diffVar = 'PSU_DIFF_{0}' -f [guid]::NewGuid().ToString('N')
        $v = "%$diffVar%"
        # The differential table. Path is the User PATH; Joins answers the joins in order and
        # PostJoin is that PATH with the approved ones applied, written out by hand. Answers
        # answers the questions that follow. Final pins the expected result for reading; the
        # oracle is the planning of PostJoin as the User PATH (its Joins are never asked).
        $diffRows = @(
            # The three cases a declined join used to hide from the other checks.
            @{ Name = 'gap 1, declined'; Path = 'C:\;Tools;Tools'; Exists = @('C:\Tools', 'Tools'); Joins = @($false); PostJoin = 'C:\;Tools;Tools'
                Answers = @($true); Final = 'C:\;Tools' }
            @{ Name = 'gap 1, approved'; Path = 'C:\;Tools;Tools'; Exists = @('C:\Tools', 'Tools'); Joins = @($true); PostJoin = 'C:\Tools;Tools'
                Answers = @(); Final = 'C:\Tools;Tools' }
            @{ Name = 'gap 2, both declined'; Path = 'C:\;Tools;C:\;Tools'; Exists = @('C:\Tools', 'Tools'); Joins = @($false, $false)
                PostJoin = 'C:\;Tools;C:\;Tools'; Answers = @($true, $true); Final = 'C:\;Tools' }
            @{ Name = 'gap 2, both approved'; Path = 'C:\;Tools;C:\;Tools'; Exists = @('C:\Tools', 'Tools'); Joins = @($true, $true)
                PostJoin = 'C:\Tools;C:\Tools'; Answers = @($true); Final = 'C:\Tools' }
            @{ Name = 'gap 2, second declined'; Path = 'C:\;Tools;C:\;Tools'; Exists = @('C:\Tools', 'Tools'); Joins = @($true, $false)
                PostJoin = 'C:\Tools;C:\;Tools'; Answers = @(); Final = 'C:\Tools;C:\;Tools' }
            @{ Name = 'gap 3, declined'; Path = 'C:\;Nosuch'; Exists = @('C:\Nosuch'); Joins = @($false); PostJoin = 'C:\;Nosuch'
                Answers = @($true); Final = 'C:\' }
            @{ Name = 'gap 3, approved'; Path = 'C:\;Nosuch'; Exists = @('C:\Nosuch'); Joins = @($true); PostJoin = 'C:\Nosuch'
                Answers = @(); Final = 'C:\Nosuch' }
            # F1: a later copy of a join, or a join that repeats an entry kept by a declined fix.
            @{ Name = 'F1 two joins and a copy'; Path = 'C:\;Tools;C:\;Tools;C:\Tools'; Exists = @('C:\Tools'); Joins = @($false, $true)
                PostJoin = 'C:\;Tools;C:\Tools;C:\Tools'; Answers = @($true, $true); Final = 'C:\;C:\Tools' }
            @{ Name = 'F1 quote declined'; Path = 'C:\Tools";C:\;Tools;C:\Tools'; Exists = @('C:\Tools'); Joins = @($true)
                PostJoin = 'C:\Tools";C:\Tools;C:\Tools'; Answers = @($false); Final = 'C:\Tools";C:\Tools;C:\Tools' }
            @{ Name = 'F1 quote approved'; Path = 'C:\Tools";C:\;Tools;C:\Tools'; Exists = @('C:\Tools'); Joins = @($true)
                PostJoin = 'C:\Tools";C:\Tools;C:\Tools'; Answers = @($true, $true, $true); Final = 'C:\Tools' }
            @{ Name = 'F1 span, join declined'; Path = '"C:\A;C:\Tools";C:\;Tools;C:\Tools'; Exists = @('C:\A', 'C:\Tools'); Joins = @($false)
                PostJoin = '"C:\A;C:\Tools";C:\;Tools;C:\Tools'; Answers = @($false, $true); Final = '"C:\A;C:\Tools";C:\;C:\Tools' }
            @{ Name = 'F1 span, join approved'; Path = '"C:\A;C:\Tools";C:\;Tools;C:\Tools;C:\A'; Exists = @('C:\A', 'C:\Tools'); Joins = @($true)
                PostJoin = '"C:\A;C:\Tools";C:\Tools;C:\Tools;C:\A'; Answers = @($false); Final = '"C:\A;C:\Tools";C:\Tools;C:\Tools;C:\A' }
            @{ Name = 'F1 copy before the join'; Path = 'C:\Tools";C:\Tools;C:\;Tools'; Exists = @('C:\Tools'); Joins = @($true)
                PostJoin = 'C:\Tools";C:\Tools;C:\Tools'; Answers = @($false); Final = 'C:\Tools";C:\Tools;C:\Tools' }
            @{ Name = 'F1 three joins'; Path = 'C:\;Tools;C:\;Tools;C:\;Tools'; Exists = @('C:\Tools'); Joins = @($false, $true, $true)
                PostJoin = 'C:\;Tools;C:\Tools;C:\Tools'; Answers = @($true, $true); Final = 'C:\;C:\Tools' }
            # F2: a half of a declined join that repeats an earlier entry.
            @{ Name = 'F2 relative half, approved'; Path = 'Tools;C:\;Tools'; Exists = @('C:\Tools', 'Tools'); Joins = @($true)
                PostJoin = 'Tools;C:\Tools'; Answers = @(); Final = 'Tools;C:\Tools' }
            @{ Name = 'F2 relative half, declined'; Path = 'Tools;C:\;Tools'; Exists = @('C:\Tools', 'Tools'); Joins = @($false)
                PostJoin = 'Tools;C:\;Tools'; Answers = @($true); Final = 'Tools;C:\' }
            @{ Name = 'F2 root half, approved'; Path = 'C:\;C:\;Tools'; Exists = @('C:\Tools'); Joins = @($true)
                PostJoin = 'C:\;C:\Tools'; Answers = @(); Final = 'C:\;C:\Tools' }
            @{ Name = 'F2 root half, declined'; Path = 'C:\;C:\;Tools'; Exists = @('C:\Tools'); Joins = @($false)
                PostJoin = 'C:\;C:\;Tools'; Answers = @($true, $false); Final = 'C:\;Tools' }
            # IncorrectSemicolons alone leaves the duplicate the join makes.
            @{ Name = 'IncorrectSemicolons only'; Path = 'C:\Tools;C:\;Tools'; Exists = @('C:\Tools'); FixTypes = @('IncorrectSemicolons'); Joins = @($true)
                PostJoin = 'C:\Tools;C:\Tools'; Answers = @(); Final = 'C:\Tools;C:\Tools' }
            # %VAR%: never joined in a REG_SZ PATH (kept, with a warning), joined in REG_EXPAND_SZ.
            @{ Name = 'REG_SZ %VAR%'; Path = "C:\;Tools\$v"; Exists = @("C:\Tools\$v", 'C:\Tools\Good'); Joins = @()
                PostJoin = "C:\;Tools\$v"; Answers = @(); Final = "C:\;Tools\$v" }
            @{ Name = 'REG_SZ %VAR% beside a join'; Path = "C:\;Tools;C:\Bin\$v"; Exists = @('C:\Tools'); Joins = @($true)
                PostJoin = "C:\Tools;C:\Bin\$v"; Answers = @(); Final = "C:\Tools;C:\Bin\$v" }
            @{ Name = 'REG_EXPAND_SZ %VAR%'; Path = "C:\;Tools\$v;C:\Tools\Good"; Kind = 'ExpandString'; Exists = @('C:\Tools\Good'); Joins = @($true)
                PostJoin = "C:\Tools\$v;C:\Tools\Good"; Answers = @(); Final = "C:\Tools\$v;C:\Tools\Good" }
            # A UNC entry, kept remotely (SkipUnc) and removed here.
            @{ Name = 'UNC'; Path = 'C:\;Tools;\\srv\share;C:\Tools'; Exists = @('C:\Tools'); Joins = @($true)
                PostJoin = 'C:\Tools;\\srv\share;C:\Tools'; Answers = @($true, $true); Final = 'C:\Tools'; RemoteFinal = 'C:\Tools;\\srv\share' }
            # A quoted span whose part the join supplies, or does not.
            @{ Name = 'span, approved'; Path = 'C:\;Tools;"C:\Tools;C:\B"'; Exists = @('C:\Tools', 'C:\B'); Joins = @($true)
                PostJoin = 'C:\Tools;"C:\Tools;C:\B"'; Answers = @($true); Final = 'C:\Tools;C:\B' }
            @{ Name = 'span, declined'; Path = 'C:\;Tools;"C:\Tools;C:\B"'; Exists = @('C:\Tools', 'C:\B'); Joins = @($false)
                PostJoin = 'C:\;Tools;"C:\Tools;C:\B"'; Answers = @($true, $true); Final = 'C:\;C:\Tools;C:\B' }
        )
        $diffCases = foreach ($mode in 'local', 'remote') {
            foreach ($row in $diffRows) { $row + @{ Mode = $mode; VarName = $diffVar } }
        }
    }

    BeforeAll {
        function New-FakeCmdlet ([bool[]]$Answers) {
            $fake = [pscustomobject]@{ Answers = $Answers; Calls = New-Object System.Collections.Generic.List[string] }
            $fake | Add-Member -MemberType ScriptMethod -Name ShouldProcess -Value {
                param($Target, $Action)
                $this.Calls.Add("$Target|$Action")
                $this.Answers[$this.Calls.Count - 1]
            }
            $fake
        }
    }

    It 'repairs <Name> (<Mode>) exactly as the PATH with only its approved joins, planned alone' -ForEach $diffCases {
        $row = $_
        $mode = $row.Mode
        [System.Environment]::SetEnvironmentVariable($row.VarName, 'Good', 'Process')
        try {
            $fixTypes = $row.FixTypes
            if (-not $fixTypes) { $fixTypes = @('UnbalancedQuotes', 'IncorrectSemicolons', 'Duplicates', 'BlankEntries', 'NonExistentPaths') }
            $kind = $row.Kind
            if (-not $kind) { $kind = 'String' }
            $params = @{ Path = $row.Path; PostJoin = $row.PostJoin; Kind = $kind; Exists = $row.Exists; FixTypes = $fixTypes; Remote = ($mode -eq 'remote')
                Actual = (New-FakeCmdlet -Answers (@($row.Joins) + @($row.Answers))); Oracle = (New-FakeCmdlet -Answers $row.Answers) }
            $outcome = InModuleScope PathRepair -Parameters $params {
                param($Path, $PostJoin, $Kind, $Exists, $FixTypes, $Remote, $Actual, $Oracle)
                $script:diffPath = $Path
                $script:diffKind = $Kind
                $script:diffExists = $Exists
                # The fake registry and folders; %VAR% is expanded unless the check is literal.
                $script:fakes = @'
function Read-UserEnvironmentValue { param($Name) [pscustomobject]@{ Value = $script:diffPath; Kind = $script:diffKind } }
function Test-PathDirectory { param([string]$Path, [switch]$Literal) $t = $Path.Trim('"'); if (-not $Literal) { $t = [System.Environment]::ExpandEnvironmentVariables($t) }; $script:diffExists -contains $t }
'@
                Mock Read-UserEnvironmentValue { [pscustomobject]@{ Value = $script:diffPath; Kind = $script:diffKind } }
                Mock Test-PathDirectory { $t = $Path.Trim('"'); if (-not $Literal) { $t = [System.Environment]::ExpandEnvironmentVariables($t) }; $script:diffExists -contains $t }
                $targetParams = @{ FixTypes = $FixTypes }
                if ($Remote) {
                    # Runs the real remote script block here, with only the registry and the
                    # folder checks replaced (defined after the block's own, before its last
                    # line, the call).
                    $script:remoteCalls = 0
                    Mock Invoke-Command {
                        $script:remoteCalls++
                        $lines = @("$ScriptBlock" -split "`n")
                        $text = (@($lines[0..($lines.Count - 2)]) + @($script:fakes) + @($lines[-1])) -join "`n"
                        & ([scriptblock]::Create($text)) @ArgumentList
                    }
                    $targetParams['ComputerName'] = 'PC01'
                }
                # 3>&1 collects the warnings shown; -WarningVariable would also hold the held-back ones.
                $output = @(Select-ApprovedPathRepair -Cmdlet $Actual -Target 'User PATH' -TargetParams $targetParams 3>&1)
                $actualWarnings = @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
                $selection = @($output | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })[-1]
                $remoteCalls = $script:remoteCalls

                # The oracle: the joined PATH as the User PATH, planned and asked with no join.
                $script:diffPath = $PostJoin
                $plan = Invoke-PathRepairCore -FixTypes $FixTypes -SkipUnc $Remote -WarningVariable oracleWarnings -WarningAction SilentlyContinue
                $oracle = Select-ApprovedPathChange -Cmdlet $Oracle -Target 'User PATH' -Plan $plan
                [pscustomobject]@{ JoinCount = @($selection.Preview.Joins).Count; RemoteCalls = $remoteCalls; Selection = $selection; Oracle = $oracle; Plan = $plan
                    ActualWarnings = @($actualWarnings | ForEach-Object { "$_" })
                    OracleWarnings = @($oracleWarnings | ForEach-Object { "$_" }) }
            }
            $because = "row '$($row.Name)' ($mode)"
            $outcome.JoinCount | Should -Be @($row.Joins).Count -Because $because
            if ($mode -eq 'remote') {
                # One call to plan the PATH as read, and one more to plan it joined.
                $expectedCalls = 1
                if (@($row.Joins | Where-Object { $_ }).Count -gt 0) { $expectedCalls = 2 }
                $outcome.RemoteCalls | Should -Be $expectedCalls -Because $because
            }
            $joinCalls = @($params.Actual.Calls | Select-Object -First $outcome.JoinCount)
            $joinCalls | ForEach-Object { $_ | Should -Match '^User PATH\|Replace entry .* \(Incorrect semicolon after drive letter\)$' -Because $because }
            @($params.Actual.Calls | Select-Object -Skip $outcome.JoinCount) | Should -Be @($params.Oracle.Calls) -Because $because
            $outcome.Selection.NewPath | Should -BeExactly $outcome.Oracle.NewPath -Because $because
            $final = $row.Final
            if ($mode -eq 'remote' -and $row.RemoteFinal) { $final = $row.RemoteFinal }
            $outcome.Selection.NewPath | Should -BeExactly $final -Because $because
            @($outcome.ActualWarnings) | Should -Be @($outcome.OracleWarnings) -Because $because
            @($outcome.Selection.Plan.Changes | ForEach-Object { "$($_.Entry)>$($_.NewEntry)>$($_.Reason)" }) |
                Should -Be @($outcome.Plan.Changes | ForEach-Object { "$($_.Entry)>$($_.NewEntry)>$($_.Reason)" }) -Because $because
        } finally {
            [System.Environment]::SetEnvironmentVariable($row.VarName, $null, 'Process')
        }
    }
}

Describe 'Repair-PathEntry -ComputerName' {
    BeforeEach {
        Mock Invoke-PathRepairCore -ModuleName PathRepair { throw 'must not run locally' }
        Mock Write-RepairedPath -ModuleName PathRepair { throw 'must not run locally' }
        Mock Invoke-Command -ModuleName PathRepair {
            if (-not $ArgumentList[0]) {
                [pscustomobject]@{
                    ComputerName = 'PC01'; OriginalPath = 'C:\Missing;C:\Good'; OriginalKind = 'ExpandString'; Entries = @('C:\Missing', 'C:\Good'); NewPath = 'C:\Good'
                    Changes = @([pscustomobject]@{ Index = 0; Entry = 'C:\Missing'; NewEntry = $null; Reason = 'Non-existent directory' })
                    Applied = $false
                }
            }
        }
    }

    It 'previews then writes the approved result through Invoke-Command, with no credential unless given' {
        $result = Repair-PathEntry -ComputerName PC01 -FixTypes NonExistentPaths -Confirm:$false
        $result.Applied | Should -BeTrue
        $result.ComputerName | Should -Be 'PC01'
        $result.NewPath | Should -Be 'C:\Good'
        Should -Invoke Invoke-Command -ModuleName PathRepair -Times 2 -Exactly -ParameterFilter {
            $ComputerName -eq 'PC01' -and $null -eq $Credential -and @($ArgumentList[1]) -join ',' -eq 'NonExistentPaths'
        }
        Should -Invoke Invoke-Command -ModuleName PathRepair -Times 1 -Exactly -ParameterFilter {
            $ArgumentList[0] -eq $true -and $ArgumentList[2] -eq 'C:\Missing;C:\Good' -and $ArgumentList[3] -eq 'C:\Good' -and
                $ArgumentList[4] -ceq 'ExpandString'
        }
    }

    It 'passes several -FixTypes to the remote computer as one argument' {
        $null = Repair-PathEntry -ComputerName PC01 -FixTypes Duplicates, NonExistentPaths -Confirm:$false
        Should -Invoke Invoke-Command -ModuleName PathRepair -Times 2 -Exactly -ParameterFilter {
            $ArgumentList.Count -eq 5 -and @($ArgumentList[1]) -join ',' -eq 'Duplicates,NonExistentPaths'
        }
        Should -Invoke Invoke-Command -ModuleName PathRepair -Times 1 -Exactly -ParameterFilter {
            $ArgumentList[0] -eq $true -and $ArgumentList[2] -eq 'C:\Missing;C:\Good' -and $ArgumentList[3] -eq 'C:\Good'
        }
    }

    It 'passes the credential, also by the old -Credentials name' {
        $cred = New-Object System.Management.Automation.PSCredential('user', (New-Object System.Security.SecureString))
        $null = Repair-PathEntry -ComputerName PC01 -Credentials $cred -WhatIf
        Should -Invoke Invoke-Command -ModuleName PathRepair -Times 1 -Exactly -ParameterFilter { $Credential.UserName -eq 'user' -and $ArgumentList[0] -eq $false }
    }

    It 'reports a remoting failure as an error naming the computer' {
        Mock Invoke-Command -ModuleName PathRepair { throw 'WinRM cannot complete the operation' }
        $null = Repair-PathEntry -ComputerName PC01 -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
        "$err" | Should -Match 'User PATH on PC01: WinRM cannot complete'
    }

    It 'sends a script block that defines every function it calls and skips UNC entries' {
        $block = InModuleScope PathRepair { Get-PathRepairRemoteScriptBlock }
        foreach ($name in 'Read-UserEnvironmentValue', 'Write-UserEnvironmentValue', 'Send-EnvironmentChange', 'Test-PathDirectory', 'Split-PathValue',
            'Invoke-PathRepairCore', 'Write-RepairedPath') {
            "$block" | Should -Match ('(?m)^function {0} \{{' -f $name)
        }
        "$block" | Should -Match 'Invoke-PathRepairCore -FixTypes \$FixTypes -SkipUnc \$true'
        "$block" | Should -Match '\[string\]\$NewPath, \[string\]\$OriginalKind\)'
        "$block" | Should -Match 'Write-RepairedPath -OriginalPath \$OriginalPath -OriginalKind \$OriginalKind -NewPath \$NewPath'
        # Run it, read-only (Apply is $false), in a fresh runspace that has no PathRepair module.
        $ps = [powershell]::Create()
        try {
            $null = $ps.AddScript("$block").AddArgument($false).AddArgument([string[]]@('Duplicates')).AddArgument('').AddArgument('').AddArgument('')
            $failure = $null
            try { $output = @($ps.Invoke()) } catch { $failure = $_.Exception.InnerException }
            # Off Windows there is no User scope, so the core's registry read throws.
            if ($failure) {
                $failure.Message | Should -Match 'exists only on Windows'
            } else {
                @($ps.Streams.Error) | Should -BeNullOrEmpty
                $output.Count | Should -Be 1
                $output[0].Applied | Should -BeFalse
            }
        } finally {
            $ps.Dispose()
        }
    }

    It 'sends a script block that also defines the join helpers and plans a joined PATH it is given' {
        $block = InModuleScope PathRepair { Get-PathRepairRemoteScriptBlock }
        foreach ($name in 'Join-SplitDriveRoot', 'Get-PathJoinCandidate') {
            "$block" | Should -Match ('(?m)^function {0} \{{' -f $name)
        }
        "$block" | Should -Match 'elseif \(\$NewPath\) \{ Invoke-PathRepairCore -FixTypes \$FixTypes -SkipUnc \$true -Value \$NewPath -Kind \$OriginalKind \}'
        # Given a PATH to plan, the block never reads the registry, so this runs on any OS.
        $ps = [powershell]::Create()
        try {
            $null = $ps.AddScript("$block").AddArgument($false).AddArgument([string[]]@('IncorrectSemicolons', 'Duplicates')).AddArgument('').AddArgument('A;A').AddArgument('ExpandString')
            $output = @($ps.Invoke())
            @($ps.Streams.Error) | Should -BeNullOrEmpty
            $output.Count | Should -Be 1
            $output[0].OriginalPath | Should -BeExactly 'A;A'
            $output[0].OriginalKind | Should -BeExactly 'ExpandString'
            $output[0].NewPath | Should -BeExactly 'A'
        } finally {
            $ps.Dispose()
        }
    }

    It 'plans the joined PATH on the remote computer and writes it against the PATH read first' {
        Mock Invoke-Command -ModuleName PathRepair {
            if ($ArgumentList[0]) { return }
            if (-not $ArgumentList[3]) {
                return [pscustomobject]@{
                    ComputerName = 'PC01'; OriginalPath = 'C:\Tools;C:\;Tools'; OriginalKind = 'String'; Entries = @('C:\Tools', 'C:\', 'Tools'); NewPath = 'C:\Tools;C:\;Tools'
                    Changes = @(); Applied = $false
                    Joins = @([pscustomobject]@{ Index = 1; Entry = 'C:\;Tools'; NewEntry = 'C:\Tools'; Reason = 'Incorrect semicolon after drive letter'; DuplicateOf = $null })
                }
            }
            [pscustomobject]@{
                ComputerName = 'PC01'; OriginalPath = $ArgumentList[3]; OriginalKind = $ArgumentList[4]; Entries = @('C:\Tools', 'C:\Tools'); NewPath = 'C:\Tools'
                Changes = @([pscustomobject]@{ Index = 1; Entry = 'C:\Tools'; NewEntry = $null; Reason = 'Duplicate entry'; DuplicateOf = 0 })
                Joins = @(); Applied = $false
            }
        }
        $result = Repair-PathEntry -ComputerName PC01 -FixTypes IncorrectSemicolons, Duplicates -Confirm:$false
        $result.Applied | Should -BeTrue
        $result.OriginalPath | Should -BeExactly 'C:\Tools;C:\;Tools'
        $result.NewPath | Should -BeExactly 'C:\Tools'
        @($result.Changes | ForEach-Object { $_.Reason }) | Should -Be @('Incorrect semicolon after drive letter', 'Duplicate entry')
        Should -Invoke Invoke-Command -ModuleName PathRepair -Times 3 -Exactly -ParameterFilter {
            $ComputerName -eq 'PC01' -and $ArgumentList.Count -eq 5 -and @($ArgumentList[1]) -join ',' -eq 'IncorrectSemicolons,Duplicates'
        }
        Should -Invoke Invoke-Command -ModuleName PathRepair -Times 1 -Exactly -ParameterFilter {
            $ArgumentList[0] -eq $false -and $ArgumentList[3] -ceq 'C:\Tools;C:\Tools' -and $ArgumentList[4] -ceq 'String'
        }
        Should -Invoke Invoke-Command -ModuleName PathRepair -Times 1 -Exactly -ParameterFilter {
            $ArgumentList[0] -eq $true -and $ArgumentList[2] -ceq 'C:\Tools;C:\;Tools' -and $ArgumentList[3] -ceq 'C:\Tools' -and $ArgumentList[4] -ceq 'String'
        }
    }

    It 'writes nothing, and names the computer, when planning the joined PATH fails' {
        Mock Invoke-Command -ModuleName PathRepair {
            if ($ArgumentList[3]) { throw 'WinRM cannot complete the operation' }
            [pscustomobject]@{
                ComputerName = 'PC01'; OriginalPath = 'C:\;Tools'; OriginalKind = 'String'; Entries = @('C:\', 'Tools'); NewPath = 'C:\;Tools'; Changes = @(); Applied = $false
                Joins = @([pscustomobject]@{ Index = 0; Entry = 'C:\;Tools'; NewEntry = 'C:\Tools'; Reason = 'Incorrect semicolon after drive letter'; DuplicateOf = $null })
            }
        }
        $result = Repair-PathEntry -ComputerName PC01 -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$err" | Should -Match 'User PATH on PC01: WinRM cannot complete'
        Should -Invoke Invoke-Command -ModuleName PathRepair -Times 2 -Exactly
        Should -Invoke Invoke-Command -ModuleName PathRepair -Times 0 -Exactly -ParameterFilter { $ArgumentList[0] -eq $true }
    }
}

Describe 'Invoke-PathRepairCore' {
    It 'keeps UNC entries from the NonExistentPaths fix only when SkipUnc is set' {
        InModuleScope PathRepair {
            Mock Read-UserEnvironmentValue { [pscustomobject]@{ Value = 'C:\Good;\\server\share;"\\server\tools";Z:\Mapped'; Kind = 'String' } }
            Mock Test-PathDirectory { $Path -eq 'C:\Good' }
            (Invoke-PathRepairCore -FixTypes NonExistentPaths -SkipUnc $true).NewPath | Should -Be 'C:\Good;\\server\share;"\\server\tools"'
            (Invoke-PathRepairCore -FixTypes NonExistentPaths).NewPath | Should -Be 'C:\Good'
        }
    }

    It 'with SkipUnc keeps a REG_EXPAND_SZ %VAR% entry that expands to a UNC share, and removes it without SkipUnc' {
        $varName = 'PSU_UNC_TEST_{0}' -f [guid]::NewGuid().ToString('N')
        [System.Environment]::SetEnvironmentVariable($varName, '\\fileserver\tools', 'Process')
        try {
            InModuleScope PathRepair -Parameters @{ VarName = $varName } {
                param($VarName)
                $script:testPath = "C:\Good;%$VarName%\bin;\\server\share;C:\Missing"
                Mock Read-UserEnvironmentValue { [pscustomobject]@{ Value = $script:testPath; Kind = 'ExpandString' } }
                Mock Test-PathDirectory { $Path -eq 'C:\Good' }
                (Invoke-PathRepairCore -FixTypes NonExistentPaths -SkipUnc $true).NewPath |
                    Should -BeExactly "C:\Good;%$VarName%\bin;\\server\share"
                (Invoke-PathRepairCore -FixTypes NonExistentPaths).NewPath | Should -BeExactly 'C:\Good'
            }
        } finally {
            [System.Environment]::SetEnvironmentVariable($varName, $null, 'Process')
        }
    }

    It 'removes a %VAR% entry that expands to <Value> only when no part is usable (existing: <Existing>, SkipUnc: <SkipUnc>)' -ForEach @(
        @{ Value = 'C:\Tools;C:\SDK'; Existing = @('C:\Tools', 'C:\SDK'); SkipUnc = $false; Kept = $true }
        @{ Value = 'C:\Tools;C:\SDK'; Existing = @('C:\SDK'); SkipUnc = $false; Kept = $true }
        @{ Value = 'C:\Tools;C:\SDK'; Existing = @(); SkipUnc = $false; Kept = $false }
        @{ Value = 'C:\Tools;;"C:\SDK"'; Existing = @('C:\SDK'); SkipUnc = $false; Kept = $true }
        @{ Value = 'C:\Tools;\\server\sdk'; Existing = @(); SkipUnc = $true; Kept = $true }
        @{ Value = 'C:\Tools;\\server\sdk'; Existing = @(); SkipUnc = $false; Kept = $false }
    ) {
        $varName = 'PSU_MULTI_TEST_{0}' -f [guid]::NewGuid().ToString('N')
        [System.Environment]::SetEnvironmentVariable($varName, $Value, 'Process')
        try {
            InModuleScope PathRepair -Parameters @{ VarName = $varName; Existing = $Existing; SkipUnc = $SkipUnc; Kept = $Kept } {
                param($VarName, $Existing, $SkipUnc, $Kept)
                $script:testPath = "C:\Good;%$VarName%"
                $script:testExisting = @('C:\Good') + $Existing
                Mock Read-UserEnvironmentValue { [pscustomobject]@{ Value = $script:testPath; Kind = 'ExpandString' } }
                Mock Test-PathDirectory { $Path.Trim('"') -in $script:testExisting }
                $result = Invoke-PathRepairCore -FixTypes NonExistentPaths -SkipUnc $SkipUnc
                if ($Kept) {
                    $result.NewPath | Should -BeExactly "C:\Good;%$VarName%"
                    @($result.Changes).Count | Should -Be 0
                } else {
                    $result.NewPath | Should -BeExactly 'C:\Good'
                    @($result.Changes)[0].Entry | Should -BeExactly "%$VarName%"
                    @($result.Changes)[0].Reason | Should -Be 'Non-existent directory'
                }
            }
        } finally {
            [System.Environment]::SetEnvironmentVariable($varName, $null, 'Process')
        }
    }

    It 'IncorrectSemicolons matches C:\;dir when an entry still holds it, as Get-MalformedPathEntry does' {
        # Unreachable through the real split (see #162), so the split is replaced here.
        InModuleScope PathRepair {
            Mock Read-UserEnvironmentValue { [pscustomobject]@{ Value = 'C:\;Good'; Kind = 'String' } }
            Mock Split-PathValue { 'C:\;Good' }
            Mock Test-PathDirectory { $Path -eq 'C:\Good' }
            $change = @((Invoke-PathRepairCore -FixTypes IncorrectSemicolons).Changes)
            $change[0].NewEntry | Should -BeExactly 'C:\Good'
            $change[0].Reason | Should -Be 'Incorrect semicolon after drive letter'
        }
    }

    It 'lists a join, checked as written in a REG_SZ PATH and expanded in a REG_EXPAND_SZ PATH, apart from Changes (<Kind>)' -ForEach @(
        @{ Kind = 'String'; ExpectLiteral = $true }
        @{ Kind = 'ExpandString'; ExpectLiteral = $false }
    ) {
        InModuleScope PathRepair -Parameters @{ Kind = $Kind; ExpectLiteral = $ExpectLiteral } {
            param($Kind, $ExpectLiteral)
            $script:testKind = $Kind
            $script:testLiteral = $ExpectLiteral
            Mock Read-UserEnvironmentValue { [pscustomobject]@{ Value = 'C:\;Tools'; Kind = $script:testKind } }
            Mock Test-PathDirectory { $Path -eq 'C:\Tools' }
            $plan = Invoke-PathRepairCore -FixTypes IncorrectSemicolons
            @($plan.Joins).Count | Should -Be 1
            @($plan.Joins)[0].Index | Should -Be 0
            @($plan.Joins)[0].Entry | Should -BeExactly 'C:\;Tools'
            @($plan.Joins)[0].NewEntry | Should -BeExactly 'C:\Tools'
            @($plan.Joins)[0].Reason | Should -Be 'Incorrect semicolon after drive letter'
            # The plan is of the PATH as read: the join is the caller's to ask about.
            @($plan.Changes).Count | Should -Be 0
            $plan.NewPath | Should -BeExactly 'C:\;Tools'
            Should -Invoke Test-PathDirectory -Times 1 -Exactly -ParameterFilter { $Path -eq 'C:\Tools' -and [bool]$PesterBoundParameters['Literal'] -eq $script:testLiteral }
        }
    }

    It 'lists a join holding %VAR% only in a REG_EXPAND_SZ PATH, and in a REG_SZ PATH warns about the half (<Kind>)' -ForEach @(
        @{ Kind = 'ExpandString'; Joined = $true }
        @{ Kind = 'String'; Joined = $false }
    ) {
        $varName = 'PSU_JOIN_TEST_{0}' -f [guid]::NewGuid().ToString('N')
        [System.Environment]::SetEnvironmentVariable($varName, 'Good', 'Process')
        try {
            InModuleScope PathRepair -Parameters @{ VarName = $varName; Kind = $Kind; Joined = $Joined } {
                param($VarName, $Kind, $Joined)
                $script:testPath = "C:\;Tools\%$VarName%"
                $script:testKind = $Kind
                Mock Read-UserEnvironmentValue { [pscustomobject]@{ Value = $script:testPath; Kind = $script:testKind } }
                # Every folder exists, literal %VAR% name included.
                Mock Test-PathDirectory { $true }
                $plan = Invoke-PathRepairCore -FixTypes IncorrectSemicolons, NonExistentPaths -WarningVariable warnings -WarningAction SilentlyContinue
                $plan.NewPath | Should -BeExactly $script:testPath
                if ($Joined) {
                    @($plan.Joins)[0].NewEntry | Should -BeExactly "C:\Tools\%$VarName%"
                    $warnings | Should -BeNullOrEmpty
                } else {
                    @($plan.Joins).Count | Should -Be 0
                    @($warnings).Count | Should -Be 1
                    "$($warnings[0])" | Should -BeLike "*'Tools\%$VarName%' kept*"
                }
            }
        } finally {
            [System.Environment]::SetEnvironmentVariable($varName, $null, 'Process')
        }
    }

    It 'lists no join unless IncorrectSemicolons is selected, and plans both halves as entries' {
        InModuleScope PathRepair {
            Mock Read-UserEnvironmentValue { [pscustomobject]@{ Value = 'C:\;Tools;C:\Good'; Kind = 'String' } }
            Mock Test-PathDirectory { $Path -in 'C:\Tools', 'C:\Good' }
            $plan = Invoke-PathRepairCore -FixTypes NonExistentPaths
            @($plan.Joins).Count | Should -Be 0
            @($plan.Changes).Count | Should -Be 1
            @($plan.Changes)[0].Entry | Should -BeExactly 'Tools'
            $plan.NewPath | Should -BeExactly 'C:\;C:\Good'
        }
    }

    It 'offers no join in a REG_EXPAND_SZ PATH when the expansion holds a semicolon' {
        $varName = 'PSU_JOIN_TEST_{0}' -f [guid]::NewGuid().ToString('N')
        [System.Environment]::SetEnvironmentVariable($varName, 'a;b', 'Process')
        try {
            InModuleScope PathRepair -Parameters @{ VarName = $varName } {
                param($VarName)
                # The folder named for the literal expansion would pass the existence check.
                Mock Test-PathDirectory { $true }
                @(Get-PathJoinCandidate -Entries 'C:\', "Tools\%$VarName%" -Literal $false).Count | Should -Be 0
                Should -Invoke Test-PathDirectory -Times 0 -Exactly
            }
        } finally {
            [System.Environment]::SetEnvironmentVariable($varName, $null, 'Process')
        }
    }

    It 'still offers a join in a REG_EXPAND_SZ PATH when the expansion is one folder, keeping the raw text' {
        $varName = 'PSU_JOIN_TEST_{0}' -f [guid]::NewGuid().ToString('N')
        [System.Environment]::SetEnvironmentVariable($varName, 'v1', 'Process')
        try {
            InModuleScope PathRepair -Parameters @{ VarName = $varName } {
                param($VarName)
                Mock Test-PathDirectory { $true }
                $joins = @(Get-PathJoinCandidate -Entries 'C:\', "Tools\%$VarName%" -Literal $false)
                $joins.Count | Should -Be 1
                $joins[0].NewEntry | Should -BeExactly "C:\Tools\%$VarName%"
            }
        } finally {
            [System.Environment]::SetEnvironmentVariable($varName, $null, 'Process')
        }
    }

    It 'refuses an explicit empty Value without reading the registry or calling Invoke-Command (<Name>)' -ForEach @(
        @{ Name = 'local'; Computer = $null }
        @{ Name = 'remote'; Computer = 'PC01' }
    ) {
        InModuleScope PathRepair -Parameters @{ Computer = $Computer } {
            param($Computer)
            Mock Read-UserEnvironmentValue { [pscustomobject]@{ Value = 'C:\A'; Kind = 'String' } }
            Mock Invoke-Command { }
            $params = @{ FixTypes = 'Duplicates'; Value = '' }
            if ($Computer) { $params['ComputerName'] = $Computer }
            { Invoke-PathRepairTarget @params } | Should -Throw '*No PATH text to plan; nothing written*'
            Should -Invoke Read-UserEnvironmentValue -Times 0 -Exactly
            Should -Invoke Invoke-Command -Times 0 -Exactly
        }
    }

    It 'plans a given Value under the given Kind without reading the User PATH' {
        InModuleScope PathRepair {
            Mock Read-UserEnvironmentValue { throw 'must not read' }
            $plan = Invoke-PathRepairCore -FixTypes Duplicates -Value 'C:\A;C:\A' -Kind ExpandString
            $plan.OriginalPath | Should -BeExactly 'C:\A;C:\A'
            $plan.OriginalKind | Should -BeExactly 'ExpandString'
            $plan.NewPath | Should -BeExactly 'C:\A'
            { Invoke-PathRepairCore -FixTypes Duplicates -Value '' -Kind String } | Should -Throw '*empty or not set*'
        }
    }
}

Describe 'Write-RepairedPath' {
    It 'writes nothing for a NewPath with no non-blank entry: [<NewPath>]' -ForEach @(
        @{ NewPath = '' }
        @{ NewPath = ';' }
        @{ NewPath = ' ;;' }
        @{ NewPath = '""' }
    ) {
        InModuleScope PathRepair -Parameters @{ NewPath = $NewPath } {
            param($NewPath)
            Mock Read-UserEnvironmentValue { [pscustomobject]@{ Value = 'C:\Missing;;'; Kind = 'String' } }
            Mock Write-UserEnvironmentValue
            Mock Send-EnvironmentChange
            { Write-RepairedPath -OriginalPath 'C:\Missing;;' -OriginalKind String -NewPath $NewPath } | Should -Throw '*would remove every User PATH entry*'
            Should -Invoke Write-UserEnvironmentValue -Times 0 -Exactly
        }
    }

    It 'refuses the separators-only PATH left by removing the one entry and keeping both blanks' {
        $fake = [pscustomobject]@{ Answers = @($true, $false, $false); Calls = 0 }
        $fake | Add-Member -MemberType ScriptMethod -Name ShouldProcess -Value { param($Target, $Action) $this.Calls++; $this.Answers[$this.Calls - 1] }
        $null = InModuleScope PathRepair -Parameters @{ Fake = $fake } {
            param($Fake)
            Mock Read-UserEnvironmentValue { [pscustomobject]@{ Value = 'C:\Missing;;'; Kind = 'String' } }
            Mock Test-PathDirectory { $false }
            Mock Write-UserEnvironmentValue
            Mock Send-EnvironmentChange
            $plan = Invoke-PathRepairCore -FixTypes BlankEntries, NonExistentPaths
            $selection = Select-ApprovedPathChange -Cmdlet $Fake -Target 'User PATH' -Plan $plan
            $selection.NewPath | Should -BeExactly ';'
            $plan.OriginalKind | Should -BeExactly 'String'
            { Write-RepairedPath -OriginalPath $plan.OriginalPath -OriginalKind $plan.OriginalKind -NewPath $selection.NewPath } | Should -Throw '*would remove every User PATH entry*'
            Should -Invoke Write-UserEnvironmentValue -Times 0 -Exactly
        }
    }

    It 'refuses, writing nothing, when the kind is now <Now> but the preview saw <Previewed>, even with the same text' -ForEach @(
        @{ Previewed = 'String'; Now = 'ExpandString' }
        @{ Previewed = 'ExpandString'; Now = 'String' }
    ) {
        InModuleScope PathRepair -Parameters @{ Previewed = $Previewed; Now = $Now } {
            param($Previewed, $Now)
            Mock Read-UserEnvironmentValue { [pscustomobject]@{ Value = '%USERPROFILE%\bin;C:\Bin;C:\Bin'; Kind = $Now } }
            Mock Write-UserEnvironmentValue
            Mock Send-EnvironmentChange
            { Write-RepairedPath -OriginalPath '%USERPROFILE%\bin;C:\Bin;C:\Bin' -OriginalKind $Previewed -NewPath '%USERPROFILE%\bin;C:\Bin' } |
                Should -Throw "*changed since the preview (its value kind is now $Now, not $Previewed); nothing written*"
            Should -Invoke Write-UserEnvironmentValue -Times 0 -Exactly
            Should -Invoke Send-EnvironmentChange -Times 0 -Exactly
        }
    }

    It 'writes BADPATH, BADPATH_SCOPE, PATH_FIX_DATE and PATH when text and kind (<Kind>) are unchanged' -ForEach @(
        @{ Kind = 'String' }
        @{ Kind = 'ExpandString' }
    ) {
        InModuleScope PathRepair -Parameters @{ Kind = $Kind } {
            param($Kind)
            $script:written = New-Object System.Collections.Generic.List[string]
            Mock Read-UserEnvironmentValue { [pscustomobject]@{ Value = '%USERPROFILE%\bin;C:\Bin;C:\Bin'; Kind = $Kind } }
            Mock Write-UserEnvironmentValue { $script:written.Add("$Name [$Kind]") }
            Mock Send-EnvironmentChange
            Write-RepairedPath -OriginalPath '%USERPROFILE%\bin;C:\Bin;C:\Bin' -OriginalKind $Kind -NewPath '%USERPROFILE%\bin;C:\Bin'
            $script:written -join ',' | Should -BeExactly "BADPATH [$Kind],BADPATH_SCOPE [String],PATH_FIX_DATE [String],PATH [$Kind]"
            Should -Invoke Write-UserEnvironmentValue -Times 1 -Exactly -ParameterFilter { $Name -eq 'PATH' -and $Value -ceq '%USERPROFILE%\bin;C:\Bin' }
            Should -Invoke Send-EnvironmentChange -Times 1 -Exactly
        }
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

    It 'Read-EnvironmentVariable reads a process variable' {
        InModuleScope PathRepair {
            $name = 'PATHREPAIR_TEST_{0}' -f [guid]::NewGuid().ToString('N')
            try {
                [System.Environment]::SetEnvironmentVariable($name, 'value', 'Process')
                Read-EnvironmentVariable -Name $name | Should -Be 'value'
                [System.Environment]::SetEnvironmentVariable($name, $null, 'Process')
                Read-EnvironmentVariable -Name $name | Should -BeNullOrEmpty
            } finally {
                [System.Environment]::SetEnvironmentVariable($name, $null, 'Process')
            }
        }
    }

    It 'Test-PathDirectory expands a %VAR% reference for the check' {
        New-Item -Path (Join-Path $TestDrive 'bin') -ItemType Directory | Out-Null
        $name = 'PATHREPAIR_TEST_{0}' -f [guid]::NewGuid().ToString('N')
        [System.Environment]::SetEnvironmentVariable($name, $TestDrive, 'Process')
        try {
            InModuleScope PathRepair -Parameters @{ Name = $name } {
                param($Name)
                Test-PathDirectory -Path ('%{0}%{1}bin' -f $Name, [System.IO.Path]::DirectorySeparatorChar) | Should -BeTrue
                Test-PathDirectory -Path ('"%{0}%{1}missing"' -f $Name, [System.IO.Path]::DirectorySeparatorChar) | Should -BeFalse
                Test-PathDirectory -Path ('%{0}%{1}bin' -f $Name, [System.IO.Path]::DirectorySeparatorChar) -Literal | Should -BeFalse
            }
        } finally {
            [System.Environment]::SetEnvironmentVariable($name, $null, 'Process')
        }
    }

    Context 'User environment registry helpers, given a stand-in key' {
        BeforeAll {
            # A stand-in for an open RegistryKey: it records every call and holds Values/Kinds.
            function New-FakeKey ([hashtable]$Values = @{}, [hashtable]$Kinds = @{}) {
                $key = [pscustomobject]@{ Values = $Values; Kinds = $Kinds; Calls = New-Object System.Collections.Generic.List[string] }
                $key | Add-Member -MemberType ScriptMethod -Name GetValue -Value {
                    param($Name, $Default, $Options)
                    $this.Calls.Add("GetValue $Name $Options")
                    if ($this.Values.ContainsKey($Name)) { $this.Values[$Name] } else { $Default }
                }
                $key | Add-Member -MemberType ScriptMethod -Name GetValueKind -Value { param($Name) $this.Kinds[$Name] }
                $key | Add-Member -MemberType ScriptMethod -Name SetValue -Value {
                    param($Name, $Value, $Kind)
                    $this.Calls.Add("SetValue $Name=$Value [$Kind]")
                }
                $key | Add-Member -MemberType ScriptMethod -Name DeleteValue -Value {
                    param($Name, $Throw)
                    $this.Calls.Add("DeleteValue $Name $Throw")
                }
                $key
            }
        }

        It 'Read-UserEnvironmentValue returns the raw text and kind, never expanding' {
            $key = New-FakeKey -Values @{ PATH = '%USERPROFILE%\bin' } -Kinds @{ PATH = [Microsoft.Win32.RegistryValueKind]::ExpandString }
            $result = InModuleScope PathRepair -Parameters @{ Key = $key } { param($Key) Read-UserEnvironmentValue -Name PATH -Key $Key }
            $result.Value | Should -BeExactly '%USERPROFILE%\bin'
            $result.Kind | Should -BeExactly 'ExpandString'
            $key.Calls | Should -Be @('GetValue PATH DoNotExpandEnvironmentNames')
        }

        It 'Read-UserEnvironmentValue gives Value and Kind $null for a missing value' {
            $key = New-FakeKey
            $result = InModuleScope PathRepair -Parameters @{ Key = $key } { param($Key) Read-UserEnvironmentValue -Name BADPATH -Key $Key }
            $result.Value | Should -BeNullOrEmpty
            $result.Kind | Should -BeNullOrEmpty
        }

        It 'Read-UserEnvironmentValue throws for a value that is not a string kind' {
            $key = New-FakeKey -Values @{ PATH = [byte[]](1, 2) } -Kinds @{ PATH = [Microsoft.Win32.RegistryValueKind]::Binary }
            { InModuleScope PathRepair -Parameters @{ Key = $key } { param($Key) Read-UserEnvironmentValue -Name PATH -Key $Key } } |
                Should -Throw '*Binary value, not a string*'
        }

        It 'Write-UserEnvironmentValue writes <Value> as <Expected>' -ForEach @(
            @{ Value = '%USERPROFILE%\bin'; Kind = 'ExpandString'; Expected = 'SetValue PATH=%USERPROFILE%\bin [ExpandString]' }
            @{ Value = '%USERPROFILE%\bin'; Kind = 'String'; Expected = 'SetValue PATH=%USERPROFILE%\bin [String]' }
            @{ Value = '%USERPROFILE%\bin'; Kind = $null; Expected = 'SetValue PATH=%USERPROFILE%\bin [ExpandString]' }
            @{ Value = 'C:\Tools'; Kind = $null; Expected = 'SetValue PATH=C:\Tools [String]' }
            @{ Value = $null; Kind = 'ExpandString'; Expected = 'DeleteValue PATH False' }
            @{ Value = ''; Kind = $null; Expected = 'DeleteValue PATH False' }
        ) {
            $key = New-FakeKey
            InModuleScope PathRepair -Parameters @{ Key = $key; Value = $Value; Kind = $Kind } {
                param($Key, $Value, $Kind)
                Write-UserEnvironmentValue -Name PATH -Value $Value -Kind $Kind -Key $Key
            }
            $key.Calls | Should -Be @($Expected)
        }

        It 'Write-UserEnvironmentValue refuses a kind other than String or ExpandString' {
            $key = New-FakeKey
            { InModuleScope PathRepair -Parameters @{ Key = $key } { param($Key) Write-UserEnvironmentValue -Name PATH -Value 'x' -Kind Binary -Key $Key } } |
                Should -Throw '*String or ExpandString*'
            $key.Calls.Count | Should -Be 0
        }
    }

    It 'the User registry helpers throw off Windows, and the broadcast only warns there' -Skip:([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        InModuleScope PathRepair {
            { Read-UserEnvironmentValue -Name PATH } | Should -Throw '*only on Windows*'
            { Write-UserEnvironmentValue -Name PATH -Value 'x' } | Should -Throw '*only on Windows*'
            Send-EnvironmentChange -WarningVariable warn -WarningAction SilentlyContinue
            @($warn).Count | Should -Be 1
            "$warn" | Should -Match 'only on Windows'
        }
    }

    It 'round-trips a REG_EXPAND_SZ value through HKCU\Environment and broadcasts after a re-import' -Skip:([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        # Windows only: a throwaway variable, deleted in finally. The real PATH is never touched.
        $name = 'PATHREPAIR_TEST_{0}' -f [guid]::NewGuid().ToString('N')
        try {
            InModuleScope PathRepair -Parameters @{ Name = $name } {
                param($Name)
                Write-UserEnvironmentValue -Name $Name -Value '%USERPROFILE%\bin' -Kind ExpandString
                $read = Read-UserEnvironmentValue -Name $Name
                $read.Value | Should -BeExactly '%USERPROFILE%\bin'
                $read.Kind | Should -BeExactly 'ExpandString'
                Write-UserEnvironmentValue -Name $Name -Value 'C:\Tools' -Kind String
                (Read-UserEnvironmentValue -Name $Name).Kind | Should -BeExactly 'String'
                Write-UserEnvironmentValue -Name $Name -Value $null
                (Read-UserEnvironmentValue -Name $Name).Value | Should -BeNullOrEmpty
                { Send-EnvironmentChange -WarningAction SilentlyContinue } | Should -Not -Throw
            }
            Import-Module (Join-Path $repoRoot 'Modules/PathRepair/PathRepair.psd1') -Force
            { InModuleScope PathRepair { Send-EnvironmentChange -WarningAction SilentlyContinue } } | Should -Not -Throw
        } finally {
            $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
            $key.DeleteValue($name, $false)
            $key.Dispose()
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
        $text | Should -Match 'Get-MalformedPathEntry -ErrorAction Stop'
    }

    It 'prints one sensor-error line and exits 1 when the module cannot be imported' {
        # Parsed only, never run: the import sits in a try whose catch writes the sentinel line.
        $script = Join-Path $repoRoot 'Scripts/System/Get-MalformedPathEntries-Sensor.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$null, [ref]$null)
        $try = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.TryStatementAst] }, $false))
        $try.Count | Should -Be 2
        $body = $try[0].Body.Extent.Text
        $body | Should -Match 'IsNullOrEmpty\(\$PSScriptRoot\)'
        $body | Should -Match 'Import-Module .* -ErrorAction Stop'
        $catch = $try[0].CatchClauses[0].Body.Extent.Text
        $catch | Should -Match "'PathRepair module not found\|Sensor error\|\{0\}' -f"
        $catch | Should -Match '(?m)^\s*exit 1\s*$'
    }

    It 'prints one sensor-error line and exits 1 when PATH is empty' {
        # Runs the real sensor in a child PowerShell whose own PATH is empty; the PATH of
        # this process and of the machine are never touched.
        $script = Join-Path $repoRoot 'Scripts/System/Get-MalformedPathEntries-Sensor.ps1'
        $powershell = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $output = @(& $powershell -NoProfile -Command "`$env:PATH = ''; & '$script'; exit `$LASTEXITCODE" 2>$null)
        $LASTEXITCODE | Should -Be 1
        $output.Count | Should -Be 1
        $output[0] | Should -Match '^PATH could not be analyzed\|Sensor error\|.*empty'
    }
}
