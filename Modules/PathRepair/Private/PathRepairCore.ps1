# The PATH repair itself, shared by the local and remote paths of Repair-PathEntry. For a
# remote computer, Get-PathRepairRemoteScriptBlock sends the definitions of the core and
# write functions and of the PathHelpers.ps1 functions they call, so the module need not be
# installed there.

function Invoke-PathRepairCore {
    <#
    .SYNOPSIS
        Works out the repaired User PATH of this computer, changing nothing.

    .DESCRIPTION
        Reads the User-scope PATH, splits it with Split-PathValue, and works out which
        entries to fix or remove for each selected issue type. Throws when the User PATH is
        empty. Writes nothing: Write-RepairedPath applies the result.

        Outputs one object with ComputerName, OriginalPath, Entries (the split entries),
        NewPath (every change applied), Changes (one object per changed entry: Index into
        Entries, Entry, NewEntry, which is $null for a removal, Reason, and DuplicateOf,
        the Index of the kept entry a Duplicate removal copies, else $null) and Applied,
        which is always $false. Private to PathRepair.

    .PARAMETER FixTypes
        Issue types to fix: UnbalancedQuotes, IncorrectSemicolons, Duplicates,
        BlankEntries, NonExistentPaths.

    .PARAMETER SkipUnc
        $true to keep UNC (\\server\share) entries that NonExistentPaths would remove. A
        remote session cannot reach network shares, so they always look missing there.

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

        [bool]$SkipUnc = $false
    )

    $pathRaw = Read-EnvironmentVariable -Name 'PATH' -Target User
    if ([string]::IsNullOrEmpty($pathRaw)) {
        throw 'The User PATH environment variable is empty or not set.'
    }

    $entries = @(Split-PathValue -Value $pathRaw.Trim(';'))
    $seenPaths = @{}
    $fixedPath = New-Object System.Collections.Generic.List[string]
    $changes = New-Object System.Collections.Generic.List[object]

    for ($index = 0; $index -lt $entries.Count; $index++) {
        $entry = $entries[$index]
        $suggested = $entry
        $reason = $null
        $remove = $false
        $duplicateOf = $null

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
        if (-not $remove -and 'Duplicates' -in $FixTypes -and $seenPaths.ContainsKey($suggested)) {
            $remove = $true
            $reason = 'Duplicate entry'
            $duplicateOf = $seenPaths[$suggested]
        }
        if (-not $remove -and 'NonExistentPaths' -in $FixTypes -and $suggested -notmatch '^[A-Z]:\\$' -and
            -not ($SkipUnc -and $suggested.Trim('"').StartsWith('\\')) -and -not (Test-PathDirectory -Path $suggested)) {
            $remove = $true
            $reason = 'Non-existent directory'
            if ($suggested -match '^"(?=[^"]*[^";\s])[^"]*;[^"]*"$') {
                $remove = $false; $suggested = @($suggested.Trim('"') -split ';' | Where-Object { $_.Trim() }) -join ';'; $reason = 'Quoted span holds several entries'
            }
        }

        if ($remove) {
            $changes.Add([pscustomobject]@{ Index = $index; Entry = $entry; NewEntry = $null; Reason = $reason; DuplicateOf = $duplicateOf })
            continue
        }
        if ($suggested -cne $entry) {
            $changes.Add([pscustomobject]@{ Index = $index; Entry = $entry; NewEntry = $suggested; Reason = $reason; DuplicateOf = $null })
        }
        $seenPaths[$suggested] = $index
        $fixedPath.Add($suggested)
    }

    [pscustomobject]@{
        ComputerName = [System.Environment]::MachineName
        OriginalPath = $pathRaw
        Entries      = $entries
        NewPath      = $fixedPath.ToArray() -join ';'
        Changes      = $changes.ToArray()
        Applied      = $false
    }
}

function Write-RepairedPath {
    <#
    .SYNOPSIS
        Writes a previewed PATH repair, provided the User PATH has not changed since.

    .DESCRIPTION
        Re-reads the User-scope PATH and throws, writing nothing, unless it still equals
        OriginalPath exactly, or when NewPath is empty but OriginalPath is not (writing an
        empty value would delete the User PATH). Otherwise writes OriginalPath to the
        User-scope BADPATH variable, User|<time> to BADPATH_SCOPE (the marker
        Restore-PathFromBackup checks against PATH_FIX_DATE), the same time to
        PATH_FIX_DATE, and then NewPath to the User-scope PATH. Outputs nothing. Private
        to PathRepair.

    .PARAMETER OriginalPath
        The User PATH the preview was computed from.

    .PARAMETER NewPath
        The repaired User PATH to write.

    .EXAMPLE
        Write-RepairedPath -OriginalPath $plan.OriginalPath -NewPath 'C:\Tools;C:\Bin'

    .EXAMPLE
        Write-RepairedPath -OriginalPath 'C:\Bin;C:\Bin' -NewPath 'C:\Bin'

    .NOTES
        Windows only: the User environment scope is stored in the registry.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$OriginalPath,

        [AllowEmptyString()]
        [string]$NewPath
    )

    $current = Read-EnvironmentVariable -Name 'PATH' -Target User
    if ($current -cne $OriginalPath) {
        throw 'The User PATH changed since the preview; nothing written.'
    }
    if ([string]::IsNullOrEmpty($NewPath)) {
        throw 'The repair would remove every User PATH entry; nothing written.'
    }
    Write-EnvironmentVariable -Name 'BADPATH' -Value $OriginalPath -Target User
    $fixDate = Get-Date -Format 'yyyy-MM-dd_HH:mm:ss'
    Write-EnvironmentVariable -Name 'BADPATH_SCOPE' -Value "User|$fixDate" -Target User
    Write-EnvironmentVariable -Name 'PATH_FIX_DATE' -Value $fixDate -Target User
    Write-EnvironmentVariable -Name 'PATH' -Value $NewPath -Target User
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
        copies only the changed text); -WhatIf still lists it. Outputs one object with
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
        Changes = @($Plan.Changes | Where-Object { $approved.ContainsKey([int]$_.Index) })
    }
}

function Get-PathRepairRemoteScriptBlock {
    <#
    .SYNOPSIS
        Builds a self-contained script block that previews or applies a repair remotely.

    .DESCRIPTION
        Returns a script block that defines Invoke-PathRepairCore, Write-RepairedPath and
        the helpers they call (Read-EnvironmentVariable, Write-EnvironmentVariable,
        Test-PathDirectory, Split-PathValue) from their current definitions. Its positional
        arguments are Apply, FixTypes, OriginalPath and NewPath: with Apply $false it calls
        Invoke-PathRepairCore with SkipUnc $true, with Apply $true it calls
        Write-RepairedPath. Pass it to Invoke-Command with -ArgumentList. Private to
        PathRepair.

    .EXAMPLE
        Invoke-Command -ComputerName PC01 -ScriptBlock (Get-PathRepairRemoteScriptBlock) -ArgumentList $false, @('Duplicates'), '', ''

    .NOTES
        None.
    #>
    [CmdletBinding()]
    [OutputType([scriptblock])]
    param ()

    $names = 'Read-EnvironmentVariable', 'Write-EnvironmentVariable', 'Test-PathDirectory', 'Split-PathValue',
        'Invoke-PathRepairCore', 'Write-RepairedPath'
    $parts = foreach ($name in $names) {
        "function $name {`n$((Get-Command -Name $name -CommandType Function).ScriptBlock)`n}"
    }
    $head = 'param([bool]$Apply, [string[]]$FixTypes, [string]$OriginalPath, [string]$NewPath)'
    $tail = 'if ($Apply) { Write-RepairedPath -OriginalPath $OriginalPath -NewPath $NewPath } else { Invoke-PathRepairCore -FixTypes $FixTypes -SkipUnc $true }'
    [scriptblock]::Create((@($head) + @($parts) + $tail) -join "`n")
}

function Invoke-PathRepairTarget {
    <#
    .SYNOPSIS
        Previews or applies a repair on this computer or, through Invoke-Command, on another.

    .DESCRIPTION
        Without Apply, calls Invoke-PathRepairCore; with Apply, calls Write-RepairedPath.
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

    .PARAMETER NewPath
        With Apply: the repaired User PATH to write.

    .EXAMPLE
        Invoke-PathRepairTarget -FixTypes Duplicates

    .EXAMPLE
        Invoke-PathRepairTarget -ComputerName PC01 -Apply -OriginalPath $plan.OriginalPath -NewPath $newPath

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

        [AllowEmptyString()]
        [string]$NewPath
    )

    if (-not $ComputerName) {
        if ($Apply) {
            return Write-RepairedPath -OriginalPath $OriginalPath -NewPath $NewPath
        }
        return Invoke-PathRepairCore -FixTypes $FixTypes
    }
    $invokeParams = @{
        ComputerName = $ComputerName
        ScriptBlock  = Get-PathRepairRemoteScriptBlock
        ArgumentList = @([bool]$Apply, $FixTypes, $OriginalPath, $NewPath)
        ErrorAction  = 'Stop'
    }
    if ($Credential) {
        $invokeParams['Credential'] = $Credential
    }
    Invoke-Command @invokeParams
}
