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

Describe 'Repair-PathEntry' {
    BeforeEach {
        $script:writes = New-Object System.Collections.Generic.List[string]
        Mock Write-EnvironmentVariable -ModuleName PathRepair { $script:writes.Add("$Target/$Name=$Value") }
        Mock Test-PathDirectory -ModuleName PathRepair { $Path.Trim('"') -like 'C:\Good*' }
        Mock Read-EnvironmentVariable -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } {
            'C:\Good;C:\Missing;c:\good;;C:\Good2"'
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
        Should -Invoke Read-EnvironmentVariable -ModuleName PathRepair -ParameterFilter { $Target -eq 'User' } -Times 2 -Exactly
    }

    It 'leaves a backup that Restore-PathFromBackup accepts without a warning' {
        $null = Repair-PathEntry -Confirm:$false
        $script:saved = @{}
        $script:writes | ForEach-Object { $n, $v = ($_ -replace '^User/', '') -split '=', 2; $script:saved[$n] = $v }
        Mock Read-EnvironmentVariable -ModuleName PathRepair -ParameterFilter { $Name -ne 'PATH' } { $script:saved[$Name] }
        Restore-PathFromBackup -WarningVariable warn -WarningAction SilentlyContinue
        $warn | Should -BeNullOrEmpty
    }

    It 'fixes only the selected issue types' {
        $result = Repair-PathEntry -FixTypes Duplicates -Confirm:$false
        $result.NewPath | Should -Be 'C:\Good;C:\Missing;;C:\Good2"'
        $script:writes[3] | Should -Be 'User/PATH=C:\Good;C:\Missing;;C:\Good2"'
    }

    It 'keeps a quoted entry and its neighbours apart, removing only the missing one' {
        Mock Read-EnvironmentVariable -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } { 'C:\Good;"C:\Good2";C:\Missing' }
        $result = Repair-PathEntry -Confirm:$false
        $result.NewPath | Should -Be 'C:\Good;"C:\Good2"'
        $script:writes[3] | Should -Be 'User/PATH=C:\Good;"C:\Good2"'
    }

    It 'keeps every existing entry between or inside stray quotes and an existing quoted C:\P;Q' {
        Mock Read-EnvironmentVariable -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } { 'C:\Keep;C:\A\bin";C:\Windows;C:\B\bin";"C:\X;C:\Y";"C:\P;Q"' }
        Mock Test-PathDirectory -ModuleName PathRepair { @('C:\Keep', 'C:\A\bin', 'C:\Windows', 'C:\B\bin', 'C:\X', 'C:\Y', 'C:\P;Q') -contains $Path.Trim('"') }
        $result = Repair-PathEntry -Confirm:$false
        $result.NewPath | Should -BeExactly 'C:\Keep;C:\A\bin;C:\Windows;C:\B\bin;C:\X;C:\Y;"C:\P;Q"'
        $script:writes[3] | Should -BeExactly 'User/PATH=C:\Keep;C:\A\bin;C:\Windows;C:\B\bin;C:\X;C:\Y;"C:\P;Q"'
    }

    It 'changes nothing under -WhatIf and returns the proposed repair' {
        $result = Repair-PathEntry -WhatIf
        $result.Applied | Should -BeFalse
        $result.NewPath | Should -Be 'C:\Good;C:\Good2'
        @($result.Changes).Count | Should -Be 4
        Should -Invoke Write-EnvironmentVariable -ModuleName PathRepair -Times 0 -Exactly
    }

    It 'changes nothing when no entry needs fixing' {
        Mock Read-EnvironmentVariable -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } { 'C:\Good;C:\' }
        $result = Repair-PathEntry -Confirm:$false
        $result.Applied | Should -BeFalse
        @($result.Changes).Count | Should -Be 0
        Should -Invoke Write-EnvironmentVariable -ModuleName PathRepair -Times 0 -Exactly
    }

    It 'IncorrectSemicolons changes nothing, because C:\;dir is split into two entries first' {
        Mock Read-EnvironmentVariable -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } { 'C:\;"Good"\' }
        $result = Repair-PathEntry -FixTypes IncorrectSemicolons -Confirm:$false
        @($result.Changes).Count | Should -Be 0
        Should -Invoke Write-EnvironmentVariable -ModuleName PathRepair -Times 0 -Exactly
    }

    It 'writes nothing when the User PATH changed between the preview and the write' {
        $script:reads = 0
        Mock Read-EnvironmentVariable -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } {
            $script:reads++
            if ($script:reads -eq 1) { 'C:\Good;C:\Missing' } else { 'C:\Good;C:\Missing;C:\JustInstalled' }
        }
        $result = Repair-PathEntry -FixTypes NonExistentPaths -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$err" | Should -Match 'User PATH changed since the preview; nothing written'
        Should -Invoke Write-EnvironmentVariable -ModuleName PathRepair -Times 0 -Exactly
    }

    It 'writes nothing when the repair would leave the User PATH empty' {
        Mock Read-EnvironmentVariable -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } { '\\server\share;Z:\Mapped' }
        $result = Repair-PathEntry -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$err" | Should -Match 'would remove every User PATH entry; nothing written'
        Should -Invoke Write-EnvironmentVariable -ModuleName PathRepair -Times 0 -Exactly
    }

    It 'writes an error and changes nothing when the User PATH is empty' {
        Mock Read-EnvironmentVariable -ModuleName PathRepair -ParameterFilter { $Name -eq 'PATH' } { '' }
        $result = Repair-PathEntry -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$err" | Should -Match 'User PATH on this computer: The User PATH environment variable is empty'
        Should -Invoke Write-EnvironmentVariable -ModuleName PathRepair -Times 0 -Exactly
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
                function script:Read-EnvironmentVariable { param($Name, $Target) 'C:\Good;C:\Missing' }
                function script:Write-EnvironmentVariable { param($Name, $Value, $Target) }
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
            Mock Read-EnvironmentVariable { 'C:\A";C:\A;C:\Win' }
            Mock Test-PathDirectory { @('C:\A', 'C:\Win') -contains $Path }
            $plan = Invoke-PathRepairCore -FixTypes UnbalancedQuotes, Duplicates, NonExistentPaths
            @($plan.Changes)[1].DuplicateOf | Should -Be 0
            $WhatIfPreference = $WhatIf
            Select-ApprovedPathChange -Cmdlet $Fake -Target 'User PATH' -Plan $plan
        }
        $fake.Calls.Count | Should -Be $Calls
        $result.NewPath | Should -BeExactly $NewPath
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

Describe 'Repair-PathEntry -ComputerName' {
    BeforeEach {
        Mock Invoke-PathRepairCore -ModuleName PathRepair { throw 'must not run locally' }
        Mock Write-RepairedPath -ModuleName PathRepair { throw 'must not run locally' }
        Mock Invoke-Command -ModuleName PathRepair {
            if (-not $ArgumentList[0]) {
                [pscustomobject]@{
                    ComputerName = 'PC01'; OriginalPath = 'C:\Missing;C:\Good'; Entries = @('C:\Missing', 'C:\Good'); NewPath = 'C:\Good'
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
        foreach ($name in 'Read-EnvironmentVariable', 'Write-EnvironmentVariable', 'Test-PathDirectory', 'Split-PathValue', 'Invoke-PathRepairCore', 'Write-RepairedPath') {
            "$block" | Should -Match ('(?m)^function {0} \{{' -f $name)
        }
        "$block" | Should -Match 'Invoke-PathRepairCore -FixTypes \$FixTypes -SkipUnc \$true'
        # Run it, read-only (Apply is $false), in a fresh runspace that has no PathRepair module.
        $ps = [powershell]::Create()
        try {
            $null = $ps.AddScript("$block").AddArgument($false).AddArgument([string[]]@('Duplicates')).AddArgument('').AddArgument('')
            $failure = $null
            try { $output = @($ps.Invoke()) } catch { $failure = $_.Exception.InnerException }
            # Off Windows there is no User scope, so the core reports an empty User PATH.
            if ($failure) {
                $failure.Message | Should -Match 'User PATH environment variable is empty'
            } else {
                @($ps.Streams.Error) | Should -BeNullOrEmpty
                $output.Count | Should -Be 1
                $output[0].Applied | Should -BeFalse
            }
        } finally {
            $ps.Dispose()
        }
    }
}

Describe 'Invoke-PathRepairCore' {
    It 'keeps UNC entries from the NonExistentPaths fix only when SkipUnc is set' {
        InModuleScope PathRepair {
            Mock Read-EnvironmentVariable { 'C:\Good;\\server\share;"\\server\tools";Z:\Mapped' }
            Mock Test-PathDirectory { $Path -eq 'C:\Good' }
            (Invoke-PathRepairCore -FixTypes NonExistentPaths -SkipUnc $true).NewPath | Should -Be 'C:\Good;\\server\share;"\\server\tools"'
            (Invoke-PathRepairCore -FixTypes NonExistentPaths).NewPath | Should -Be 'C:\Good'
        }
    }

    It 'IncorrectSemicolons matches C:\;dir when an entry still holds it, as Get-MalformedPathEntry does' {
        # Unreachable through the real split (see #162), so the split is replaced here.
        InModuleScope PathRepair {
            Mock Read-EnvironmentVariable { 'C:\;Good' }
            Mock Split-PathValue { 'C:\;Good' }
            Mock Test-PathDirectory { $Path -eq 'C:\Good' }
            $change = @((Invoke-PathRepairCore -FixTypes IncorrectSemicolons).Changes)
            $change[0].NewEntry | Should -BeExactly 'C:\Good'
            $change[0].Reason | Should -Be 'Incorrect semicolon after drive letter'
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
