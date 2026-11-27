# The PATH repair itself, shared by the local and remote paths of Repair-PathEntry. For a
# remote computer, Get-PathRepairRemoteScriptBlock sends the definitions of the core and
# write functions and of the PathHelpers.ps1 functions they call, so the module need not be
# installed there.

function Invoke-PathRepairCore {
    <#
    .SYNOPSIS
        Works out the repaired User PATH of this computer, changing nothing.

    .DESCRIPTION
        Reads the raw User-scope PATH (Read-UserEnvironmentValue, so %VAR% references stay
        as written), or takes Value and Kind instead, splits it with Split-PathValue, and
        works out which entries to fix or remove for each selected issue type. For a REG_EXPAND_SZ PATH, directory checks
        expand %VAR% for the check only; duplicates are compared by their text as written,
        so %USERPROFILE%\bin and its expansion are two different entries. An entry whose
        %VAR% reference this process cannot expand is never removed as non-existent, and
        one whose %VAR% expands to several entries (a value holding ';') is removed only
        when none of them is an existing directory.

        Windows does not expand %VAR% in a REG_SZ PATH, so there an entry holding a %VAR%
        reference is checked as written. It is never removed as non-existent (the user
        means the expanded folder): it is kept and a warning names it and suggests making
        PATH REG_EXPAND_SZ, even when a folder with that literal name exists. The value kind
        is never changed. Throws when the User PATH is empty. Writes nothing: Write-RepairedPath
        applies the result.

        With IncorrectSemicolons selected, Joins lists the split drive roots that
        Get-PathJoinCandidate finds in Entries. They are not part of Changes or NewPath: the
        caller asks about them first, then plans the PATH with the approved joins applied by
        calling this function again with Value and Kind.

        Outputs one object with ComputerName, OriginalPath, OriginalKind (the registry
        value kind of PATH, String or ExpandString, that the checks above assumed),
        Entries (the split entries), NewPath (every change applied), Changes (one object per changed entry: Index into
        Entries, Entry, NewEntry, which is $null for a removal, Reason, and DuplicateOf,
        the Index of the kept entry a Duplicate removal copies, else $null), Joins (the
        candidate joins, in the same form, empty unless IncorrectSemicolons is selected) and
        Applied, which is always $false. Private to PathRepair.

    .PARAMETER FixTypes
        Issue types to fix: UnbalancedQuotes, IncorrectSemicolons, Duplicates,
        BlankEntries, NonExistentPaths.

    .PARAMETER SkipUnc
        $true to keep UNC (\\server\share) entries that NonExistentPaths would remove,
        whether UNC as written or once their %VAR% is expanded (for a %VAR% that expands to
        several entries, any UNC one keeps the entry). A remote session cannot reach
        network shares, so they always look missing there.

    .PARAMETER Value
        A PATH value to plan instead of the User PATH, such as the User PATH with the
        approved joins applied. Read-UserEnvironmentValue is then not called.

    .PARAMETER Kind
        With Value: the registry value kind (String or ExpandString) to check it under.

    .EXAMPLE
        Invoke-PathRepairCore -FixTypes Duplicates

    .EXAMPLE
        Invoke-PathRepairCore -FixTypes NonExistentPaths -SkipUnc $true

    .NOTES
        Windows only: the User environment scope is stored in the registry.
    #>
    [CmdletBinding()]
    param (
        [string[]]$FixTypes,

        [bool]$SkipUnc = $false,

        [string]$Value,

        [string]$Kind
    )

    if ($PSBoundParameters.ContainsKey('Value')) {
        $pathValue = [pscustomobject]@{ Value = $Value; Kind = $Kind }
    } else {
        $pathValue = Read-UserEnvironmentValue -Name 'PATH'
    }
    $pathRaw = $pathValue.Value
    if ([string]::IsNullOrEmpty($pathRaw)) {
        throw 'The User PATH environment variable is empty or not set.'
    }
    # Windows expands %VAR% only in a REG_EXPAND_SZ value, so a REG_SZ entry means its text.
    $literalKind = $pathValue.Kind -eq 'String'

    # Not trimmed: a leading or trailing empty entry is a blank entry like any other, so it is
    # removed only through BlankEntries and ShouldProcess, and kept when BlankEntries is off.
    $entries = @(Split-PathValue -Value $pathRaw)
    $joins = @()
    if ('IncorrectSemicolons' -in $FixTypes) {
        $joins = @(Get-PathJoinCandidate -Entries $entries -Literal $literalKind)
    }
    $seenPaths = @{}
    $fixedPath = New-Object System.Collections.Generic.List[string]
    $changes = New-Object System.Collections.Generic.List[object]
    # Entries kept exactly as they are, with no change of their own that could be declined.
    $stablePaths = @{}
    # Parts kept from an unquoted span, mapped to that span's index: they reach PATH only if
    # that span's change is approved.
    $spanParts = @{}

    for ($index = 0; $index -lt $entries.Count; $index++) {
        $entry = $entries[$index]
        $suggested = $entry
        $reason = $null
        $remove = $false
        $duplicateOf = $null
        $dependsOn = @()
        $fallbackEntry = $null

        if ('UnbalancedQuotes' -in $FixTypes -and (($entry -split '"').Count - 1) % 2 -ne 0) {
            $suggested = $entry -replace '"', ''
            $reason = 'Unbalanced double-quotes'
        }
        if ('IncorrectSemicolons' -in $FixTypes -and $entry -match '^[A-Z]:\\;') {
            $corrected = $entry -replace ':\\;', ':\'
            if (Test-PathDirectory -Path $corrected) {
                $suggested = $corrected
                $reason = 'Incorrect semicolon after drive letter'
            } else {
                $remove = $true
                $reason = 'Incorrect semicolon after drive letter, no valid path found'
            }
        }
        if (-not $remove -and 'BlankEntries' -in $FixTypes -and [string]::IsNullOrWhiteSpace($entry)) {
            $remove = $true
            $reason = 'Empty or blank entry'
        }
        # Blank entries belong to BlankEntries alone, so two of them are never duplicates.
        if (-not $remove -and 'Duplicates' -in $FixTypes -and -not [string]::IsNullOrWhiteSpace($suggested) -and $seenPaths.ContainsKey($suggested)) {
            $remove = $true
            $reason = 'Duplicate entry'
            $duplicateOf = $seenPaths[$suggested]
        }
        # In a REG_SZ PATH Windows never expands this entry's %VAR%, so it is kept and reported.
        $unexpanded = $literalKind -and $suggested -match '%[^%;]+%'
        # A drive root, with or without a balanced pair of quotes, is never removed, nor is an
        # entry whose %VAR% this process cannot expand (the variable may be newer than it).
        $missing = $false
        if (-not $remove -and 'NonExistentPaths' -in $FixTypes -and -not $unexpanded -and $suggested -notmatch '^("?)[A-Z]:\\\1$') {
            $expanded = [System.Environment]::ExpandEnvironmentVariables($suggested)
            if ($expanded -notmatch '%[^%;]+%') {
                if ($expanded.Contains(';') -and -not $suggested.Contains(';')) {
                    # A %VAR% that expands to several entries: removed only when none of them
                    # exists. With SkipUnc, a UNC part keeps the entry.
                    $missing = $true
                    foreach ($part in @($expanded.Trim('"') -split ';' | Where-Object { $_.Trim() })) {
                        if (($SkipUnc -and $part.Trim('"').StartsWith('\\')) -or (Test-PathDirectory -Path $part -Literal)) {
                            $missing = $false
                            break
                        }
                    }
                } else {
                    # SkipUnc keeps an entry that is UNC as written or once its %VAR% is expanded.
                    $isUnc = $suggested.Trim('"').StartsWith('\\') -or $expanded.Trim('"').StartsWith('\\')
                    $missing = -not ($SkipUnc -and $isUnc) -and -not (Test-PathDirectory -Path $suggested)
                }
            }
        }
        if ($missing) {
            $remove = $true
            $reason = 'Non-existent directory'
            if ($suggested -match '^"(?=[^"]*[^";\s])[^"]*;[^"]*"$') {
                $remove = $false
                $reason = 'Quoted span holds several entries'
                $parts = @($suggested.Trim('"') -split ';' | Where-Object { $_.Trim() })
                if ('Duplicates' -in $FixTypes) {
                    # Drop a part that repeats an earlier part of this span, or an earlier entry
                    # that is kept as it is. A part that repeats an entry with its own pending
                    # change stays, because that change can still be declined.
                    $spanSeen = @{}
                    $unique = @($parts | Where-Object {
                        $isDuplicate = $spanSeen.ContainsKey($_) -or $stablePaths.ContainsKey($_)
                        $spanSeen[$_] = $true
                        -not $isDuplicate
                    })
                    # A part kept from an earlier span is dropped too, but that span's change
                    # can be declined, so the change carries the replacement to use instead.
                    $crossSpan = @($unique | Where-Object { -not $spanParts.ContainsKey($_) })
                    if ($crossSpan.Count -lt $unique.Count) {
                        $dependsOn = @($unique | Where-Object { $spanParts.ContainsKey($_) } |
                            ForEach-Object { $spanParts[$_] } | Select-Object -Unique)
                        $fallbackEntry = $unique -join ';'
                    }
                    if ($crossSpan.Count -lt $parts.Count) {
                        $reason = 'Quoted span holds several entries, duplicates dropped'
                    }
                    $parts = $crossSpan
                }
                if ($parts.Count -eq 0) {
                    $remove = $true
                    $reason = 'Quoted span holds only duplicate entries'
                } else {
                    $suggested = $parts -join ';'
                }
            }
        }

        if ($remove) {
            $changes.Add([pscustomobject]@{ Index = $index; Entry = $entry; NewEntry = $null; Reason = $reason; DuplicateOf = $duplicateOf
                DependsOn = $dependsOn; FallbackEntry = $fallbackEntry })
            continue
        }
        if ($suggested -cne $entry) {
            $changes.Add([pscustomobject]@{ Index = $index; Entry = $entry; NewEntry = $suggested; Reason = $reason; DuplicateOf = $null
                DependsOn = $dependsOn; FallbackEntry = $fallbackEntry })
        }
        if ($unexpanded) {
            Write-Warning ("User PATH entry '$suggested' kept: the User PATH is REG_SZ, so Windows does not expand " +
                'its %VAR% references. Make PATH REG_EXPAND_SZ to have it expanded.')
        }
        $seenPaths[$suggested] = $index
        if ($suggested -ceq $entry) {
            $stablePaths[$suggested] = $true
        } elseif ($reason -like 'Quoted span holds several entries*') {
            # Each part of an unquoted span is an entry of its own from here on, so a later
            # copy of a part is a duplicate of this span, skipped if the span is declined.
            foreach ($part in $suggested -split ';') {
                if (-not $seenPaths.ContainsKey($part)) { $seenPaths[$part] = $index }
                if (-not $spanParts.ContainsKey($part)) { $spanParts[$part] = $index }
            }
        }
        $fixedPath.Add($suggested)
    }

    [pscustomobject]@{
        ComputerName = [System.Environment]::MachineName
        OriginalPath = $pathRaw
        OriginalKind = $pathValue.Kind
        Entries      = $entries
        NewPath      = $fixedPath.ToArray() -join ';'
        Changes      = $changes.ToArray()
        Joins        = $joins
        Applied      = $false
    }
}

function Get-PathJoinCandidate {
    <#
    .SYNOPSIS
        Finds the PATH entries split in two by a semicolon after a drive root.

    .DESCRIPTION
        For each entry that Join-SplitDriveRoot can join with the entry after it (a bare
        drive root then a relative entry, as in C:\;Program Files\Foo), outputs one join when
        the joined path is an existing directory. With Literal (a REG_SZ PATH, where Windows
        does not expand %VAR%) the joined path is checked as written, and a joined path
        holding a %VAR% reference is never offered: a folder of that literal name is not the
        one meant. Otherwise %VAR% is expanded for the check. A joined path starts with a
        drive root, so it is never UNC. The entry after a drive root is never itself a drive
        root, so two joins never share an entry.

        Each join has Index (the drive root's index in Entries; the join also takes the
        entry at Index + 1), Entry (the pair as it appears in PATH, C:\;Program Files\Foo),
        NewEntry (the joined path), Reason, and DuplicateOf, which is always $null. Private
        to PathRepair.

    .PARAMETER Entries
        The split PATH entries.

    .PARAMETER Literal
        $true for a REG_SZ PATH.

    .EXAMPLE
        Get-PathJoinCandidate -Entries 'C:\', 'Tools' -Literal $true

    .EXAMPLE
        Get-PathJoinCandidate -Entries @(Split-PathValue -Value $pathRaw) -Literal $false

    .NOTES
        None.
    #>
    [CmdletBinding()]
    param (
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [string[]]$Entries,

        [bool]$Literal
    )

    for ($index = 0; $index + 1 -lt $Entries.Count; $index++) {
        $joined = Join-SplitDriveRoot -Entry $Entries[$index] -Next $Entries[$index + 1]
        if ($joined -and -not ($Literal -and $joined -match '%[^%;]+%') -and (Test-PathDirectory -Path $joined -Literal:$Literal)) {
            [pscustomobject]@{ Index = $index; Entry = "$($Entries[$index]);$($Entries[$index + 1])"; NewEntry = $joined
                Reason = 'Incorrect semicolon after drive letter'; DuplicateOf = $null }
        }
    }
}

function Write-RepairedPath {
    <#
    .SYNOPSIS
        Writes a previewed PATH repair, provided the User PATH has not changed since.

    .DESCRIPTION
        Re-reads the raw User-scope PATH and its registry value kind, and throws, writing
        nothing, unless the text still equals OriginalPath exactly and the kind still equals
        OriginalKind (the preview checked %VAR% entries under that kind's expansion rule),
        or when NewPath has no non-blank entry, such as '' or ';' (it would delete or empty the User PATH). Otherwise
        writes OriginalPath to the User-scope BADPATH variable, User|<time> to BADPATH_SCOPE
        (the marker Restore-PathFromBackup checks against PATH_FIX_DATE), the same time to
        PATH_FIX_DATE, and then NewPath to the User-scope PATH. BADPATH and PATH are
        written with the kind PATH had, so REG_EXPAND_SZ and its %VAR% text survive. Then
        broadcasts the change with Send-EnvironmentChange, which only warns when it fails,
        so a completed write is never reported as failed. Outputs nothing. Private to
        PathRepair.

    .PARAMETER OriginalPath
        The User PATH the preview was computed from.

    .PARAMETER OriginalKind
        The registry value kind (String or ExpandString) the User PATH had when the
        preview was computed, the OriginalKind of the Invoke-PathRepairCore result.

    .PARAMETER NewPath
        The repaired User PATH to write.

    .EXAMPLE
        Write-RepairedPath -OriginalPath $plan.OriginalPath -OriginalKind $plan.OriginalKind -NewPath 'C:\Tools;C:\Bin'

    .EXAMPLE
        Write-RepairedPath -OriginalPath 'C:\Bin;C:\Bin' -OriginalKind String -NewPath 'C:\Bin'

    .NOTES
        Windows only: the User environment scope is stored in the registry. The Machine
        PATH is never written.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$OriginalPath,

        [Parameter(Mandatory = $true)]
        [string]$OriginalKind,

        [AllowEmptyString()]
        [string]$NewPath
    )

    $current = Read-UserEnvironmentValue -Name 'PATH'
    if ($current.Value -cne $OriginalPath) {
        throw 'The User PATH changed since the preview; nothing written.'
    }
    # The kind decides whether %VAR% is expanded, which the preview's checks depended on.
    if ([string]$current.Kind -cne $OriginalKind) {
        throw "The User PATH changed since the preview (its value kind is now $($current.Kind), not $OriginalKind); nothing written."
    }
    # Only separators (';') or blanks would leave a User PATH with no entry at all.
    if (@($NewPath -split ';' | Where-Object { ($_ -replace '"', '').Trim() }).Count -eq 0) {
        throw 'The repair would remove every User PATH entry; nothing written.'
    }
    Write-UserEnvironmentValue -Name 'BADPATH' -Value $OriginalPath -Kind $current.Kind
    $fixDate = Get-Date -Format 'yyyy-MM-dd_HH:mm:ss'
    Write-UserEnvironmentValue -Name 'BADPATH_SCOPE' -Value "User|$fixDate" -Kind String
    Write-UserEnvironmentValue -Name 'PATH_FIX_DATE' -Value $fixDate -Kind String
    Write-UserEnvironmentValue -Name 'PATH' -Value $NewPath -Kind $current.Kind
    Send-EnvironmentChange
}

function Select-ApprovedPathChange {
    <#
    .SYNOPSIS
        Asks ShouldProcess about each previewed change and builds the PATH to write.

    .DESCRIPTION
        Calls ShouldProcess on Cmdlet once per change in Plan, then rebuilds the PATH from
        Plan.Entries: an approved change is applied (its NewEntry, or nothing for a
        removal) and every other entry is kept exactly as it is. Changes are matched by
        position, so two entries with the same text are decided separately. A Duplicate
        removal whose DuplicateOf entry had its change declined is skipped unasked (it
        copies only the changed text); -WhatIf still lists it. A change whose DependsOn
        holds a declined change is offered with its FallbackEntry instead, the replacement
        that keeps the parts the declined change would have supplied. Outputs one object with
        NewPath and Changes (the approved ones). Private to PathRepair.

    .PARAMETER Cmdlet
        The calling cmdlet ($PSCmdlet), or any object with a ShouldProcess(target, action)
        method that returns a bool.

    .PARAMETER Target
        The ShouldProcess target text, such as 'User PATH on PC01'.

    .PARAMETER Plan
        The output of Invoke-PathRepairCore.

    .EXAMPLE
        Select-ApprovedPathChange -Cmdlet $PSCmdlet -Target 'User PATH on this computer' -Plan $plan

    .EXAMPLE
        (Select-ApprovedPathChange -Cmdlet $PSCmdlet -Target $target -Plan $plan).NewPath

    .NOTES
        None.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $Cmdlet,

        [Parameter(Mandatory = $true)]
        [string]$Target,

        [Parameter(Mandatory = $true)]
        $Plan
    )

    $approved = @{}
    $declined = @{}
    foreach ($change in @($Plan.Changes)) {
        if ($null -ne $change.DuplicateOf -and $declined.ContainsKey([int]$change.DuplicateOf) -and -not $WhatIfPreference) {
            Write-Verbose "Keeping entry '$($change.Entry)': the change to the entry it duplicates was declined."
            continue
        }
        if (@($change.DependsOn | Where-Object { $declined.ContainsKey([int]$_) }).Count -gt 0 -and -not $WhatIfPreference) {
            $change = [pscustomobject]@{ Index = $change.Index; Entry = $change.Entry; NewEntry = $change.FallbackEntry
                Reason = 'Quoted span holds several entries'; DuplicateOf = $null; DependsOn = @(); FallbackEntry = $null }
        }
        if ($null -eq $change.NewEntry) {
            $action = "Remove entry '$($change.Entry)' ($($change.Reason))"
        } else {
            $action = "Replace entry '$($change.Entry)' with '$($change.NewEntry)' ($($change.Reason))"
        }
        if ($Cmdlet.ShouldProcess($Target, $action)) {
            $approved[[int]$change.Index] = $change
        } else {
            $declined[[int]$change.Index] = $true
        }
    }

    $kept = New-Object System.Collections.Generic.List[string]
    $entries = @($Plan.Entries)
    for ($index = 0; $index -lt $entries.Count; $index++) {
        if (-not $approved.ContainsKey($index)) {
            $kept.Add($entries[$index])
        } elseif ($null -ne $approved[$index].NewEntry) {
            $kept.Add($approved[$index].NewEntry)
        }
    }

    [pscustomobject]@{
        NewPath = $kept.ToArray() -join ';'
        # The approved changes as applied, so a fallback replacement is reported as written.
        Changes = @($approved.Keys | Sort-Object | ForEach-Object { $approved[$_] })
    }
}

function Select-ApprovedPathRepair {
    <#
    .SYNOPSIS
        Plans a PATH repair in two phases, the joins and then the rest, asking about each change.

    .DESCRIPTION
        Phase 1 plans the User PATH as read, with Invoke-PathRepairTarget (so on the target
        computer), calls ShouldProcess on Cmdlet once per join in the plan's Joins, and
        applies only the approved ones to its Entries. Under -WhatIf every join is listed and
        assumed approved, so the preview shows the whole repair. Phase 2 plans that PATH
        again with Invoke-PathRepairTarget (Value set to it, Kind to the kind read in phase
        1) and passes the plan to Select-ApprovedPathChange. With no join approved, the
        phase 1 plan is the phase 2 plan, so a PATH with no join, or whose joins are all
        declined, is repaired exactly as it is without joins: both halves of a declined join
        are left to the other checks. A join whose result repeats an earlier entry is two
        questions, the join and then the duplicate removal. The warnings of the plan used
        in phase 2 are shown, once, before its questions; those of a phase 1 plan that is
        planned again are not.

        Outputs one object with Preview (the phase 1 plan: ComputerName, OriginalPath and
        OriginalKind of the PATH as read), Plan (the phase 2 plan), NewPath (the PATH to
        write), Changes (the approved joins, then the approved phase 2 changes; under
        -WhatIf none, so nothing is written) and Proposed (the approved or, under -WhatIf,
        assumed joins, then every change in Plan: the repair as previewed). When either plan
        fails, writes an error naming Target, asks nothing more and outputs nothing.
        Private to PathRepair.

    .PARAMETER Cmdlet
        The calling cmdlet ($PSCmdlet), or any object with a ShouldProcess(target, action)
        method that returns a bool.

    .PARAMETER Target
        The ShouldProcess target text, such as 'User PATH on PC01'.

    .PARAMETER TargetParams
        The FixTypes, ComputerName and Credential parameters for Invoke-PathRepairTarget.

    .EXAMPLE
        Select-ApprovedPathRepair -Cmdlet $PSCmdlet -Target 'User PATH on this computer' -TargetParams @{ FixTypes = $FixTypes }

    .EXAMPLE
        (Select-ApprovedPathRepair -Cmdlet $PSCmdlet -Target $target -TargetParams $targetParams).NewPath

    .NOTES
        None.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $Cmdlet,

        [Parameter(Mandatory = $true)]
        [string]$Target,

        [Parameter(Mandatory = $true)]
        [hashtable]$TargetParams
    )

    # Warnings come back in the output (3>&1), to be shown only for the plan that is used.
    try {
        $output = @(Invoke-PathRepairTarget @TargetParams 3>&1)
    } catch {
        Write-Error "An error occurred while processing the $Target`: $($_.Exception.Message)"
        return
    }
    $warnings = @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    $preview = @($output | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })[-1]

    $approved = @{}
    # The joins actually approved: under -WhatIf none is, so nothing is written.
    $confirmed = @{}
    foreach ($join in @($preview.Joins | Where-Object { $null -ne $_ })) {
        $action = "Replace entry '$($join.Entry)' with '$($join.NewEntry)' ($($join.Reason))"
        # ShouldProcess returns $false under -WhatIf, after listing the join.
        if ($Cmdlet.ShouldProcess($Target, $action)) {
            $confirmed[[int]$join.Index] = $true
            $approved[[int]$join.Index] = $join
        } elseif ($WhatIfPreference) {
            $approved[[int]$join.Index] = $join
        }
    }

    $plan = $preview
    if ($approved.Count -gt 0) {
        $joined = New-Object System.Collections.Generic.List[string]
        $entries = @($preview.Entries)
        for ($index = 0; $index -lt $entries.Count; $index++) {
            if ($approved.ContainsKey($index)) {
                $joined.Add($approved[$index].NewEntry)
                $index++
            } else {
                $joined.Add($entries[$index])
            }
        }
        try {
            $output = @(Invoke-PathRepairTarget @TargetParams -Value ($joined.ToArray() -join ';') -Kind $preview.OriginalKind 3>&1)
        } catch {
            Write-Error "An error occurred while processing the $Target`: $($_.Exception.Message)"
            return
        }
        $warnings = @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $plan = @($output | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })[-1]
    }
    foreach ($warning in $warnings) {
        Write-Warning $warning.Message
    }
    $joins = @($approved.Keys | Sort-Object | ForEach-Object { $approved[$_] })
    $selection = Select-ApprovedPathChange -Cmdlet $Cmdlet -Target $Target -Plan $plan

    [pscustomobject]@{
        Preview  = $preview
        Plan     = $plan
        NewPath  = $selection.NewPath
        Changes  = @($joins | Where-Object { $confirmed.ContainsKey([int]$_.Index) }) + @($selection.Changes)
        Proposed = @($joins) + @($plan.Changes)
    }
}

function Get-PathRepairRemoteScriptBlock {
    <#
    .SYNOPSIS
        Builds a self-contained script block that previews or applies a repair remotely.

    .DESCRIPTION
        Returns a script block that defines Invoke-PathRepairCore, Write-RepairedPath and
        the helpers they call (Read-UserEnvironmentValue, Write-UserEnvironmentValue,
        Send-EnvironmentChange, Test-PathDirectory, Join-SplitDriveRoot,
        Get-PathJoinCandidate, Split-PathValue) from their current definitions. Its positional
        arguments are Apply, FixTypes, OriginalPath, NewPath and OriginalKind: with Apply $false it calls
        Invoke-PathRepairCore with SkipUnc $true, on the User PATH or, when NewPath is not
        empty, on NewPath (the User PATH with the approved joins applied) as a value of kind
        OriginalKind. With Apply $true it calls Write-RepairedPath. Pass it to Invoke-Command
        with -ArgumentList. Private to PathRepair.

    .EXAMPLE
        Invoke-Command -ComputerName PC01 -ScriptBlock (Get-PathRepairRemoteScriptBlock) -ArgumentList $false, @('Duplicates'), '', '', ''

    .NOTES
        None.
    #>
    [CmdletBinding()]
    [OutputType([scriptblock])]
    param ()

    $names = 'Read-UserEnvironmentValue', 'Write-UserEnvironmentValue', 'Send-EnvironmentChange', 'Test-PathDirectory',
        'Join-SplitDriveRoot', 'Get-PathJoinCandidate', 'Split-PathValue', 'Invoke-PathRepairCore', 'Write-RepairedPath'
    $parts = foreach ($name in $names) {
        "function $name {`n$((Get-Command -Name $name -CommandType Function).ScriptBlock)`n}"
    }
    $head = 'param([bool]$Apply, [string[]]$FixTypes, [string]$OriginalPath, [string]$NewPath, [string]$OriginalKind)'
    $tail = 'if ($Apply) { Write-RepairedPath -OriginalPath $OriginalPath -OriginalKind $OriginalKind -NewPath $NewPath } ' +
        'elseif ($NewPath) { Invoke-PathRepairCore -FixTypes $FixTypes -SkipUnc $true -Value $NewPath -Kind $OriginalKind } ' +
        'else { Invoke-PathRepairCore -FixTypes $FixTypes -SkipUnc $true }'
    [scriptblock]::Create((@($head) + @($parts) + $tail) -join "`n")
}

function Invoke-PathRepairTarget {
    <#
    .SYNOPSIS
        Previews or applies a repair on this computer or, through Invoke-Command, on another.

    .DESCRIPTION
        Without Apply, calls Invoke-PathRepairCore, on the User PATH or, given Value, on
        Value as a PATH of kind Kind; with Apply, calls Write-RepairedPath.
        Without ComputerName this runs here. With it, runs the script block from
        Get-PathRepairRemoteScriptBlock on that computer with -ErrorAction Stop, so a
        remoting or repair failure throws. Outputs what the called function outputs.
        Private to PathRepair.

    .PARAMETER FixTypes
        Issue types to fix, passed to Invoke-PathRepairCore.

    .PARAMETER ComputerName
        Remote computer. Omit it for this computer.

    .PARAMETER Credential
        Credential for the remote connection; omitted from Invoke-Command when $null.

    .PARAMETER Apply
        Write the repair instead of previewing it.

    .PARAMETER OriginalPath
        With Apply: the User PATH the preview was computed from.

    .PARAMETER OriginalKind
        With Apply: the registry value kind the User PATH had in the preview.

    .PARAMETER NewPath
        With Apply: the repaired User PATH to write.

    .PARAMETER Value
        Without Apply: a PATH value to plan instead of the User PATH (the User PATH with the
        approved joins applied). Remotely it is sent in the NewPath argument.

    .PARAMETER Kind
        With Value: the registry value kind the User PATH had when it was read.

    .EXAMPLE
        Invoke-PathRepairTarget -FixTypes Duplicates

    .EXAMPLE
        Invoke-PathRepairTarget -ComputerName PC01 -Apply -OriginalPath $plan.OriginalPath -OriginalKind $plan.OriginalKind -NewPath $newPath

    .NOTES
        The remote form needs PowerShell remoting (WinRM) on the target.
    #>
    [CmdletBinding()]
    param (
        [string[]]$FixTypes,

        [string]$ComputerName,

        [pscredential]$Credential,

        [switch]$Apply,

        [string]$OriginalPath,

        [string]$OriginalKind,

        [AllowEmptyString()]
        [string]$NewPath,

        [string]$Value,

        [string]$Kind
    )

    if (-not $ComputerName) {
        if ($Apply) {
            return Write-RepairedPath -OriginalPath $OriginalPath -OriginalKind $OriginalKind -NewPath $NewPath
        }
        if ($Value) {
            return Invoke-PathRepairCore -FixTypes $FixTypes -Value $Value -Kind $Kind
        }
        return Invoke-PathRepairCore -FixTypes $FixTypes
    }
    $arguments = @([bool]$Apply, $FixTypes, $OriginalPath, $NewPath, $OriginalKind)
    if (-not $Apply -and $Value) {
        $arguments = @($false, $FixTypes, '', $Value, $Kind)
    }
    $invokeParams = @{
        ComputerName = $ComputerName
        ScriptBlock  = Get-PathRepairRemoteScriptBlock
        ArgumentList = $arguments
        ErrorAction  = 'Stop'
    }
    if ($Credential) {
        $invokeParams['Credential'] = $Credential
    }
    Invoke-Command @invokeParams
}
