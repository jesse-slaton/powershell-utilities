function Get-MalformedPathEntry {
    <#
    .SYNOPSIS
        Reports malformed entries in the PATH environment variable of the current process.

    .DESCRIPTION
        Splits the current process PATH (the merged Machine and User PATH) on semicolons
        outside double quotes (on every semicolon when the quotes are unbalanced) and checks
        each entry for:
        - Unbalanced double quotes
        - A semicolon after a drive root that splits one entry in two: a bare drive root
          followed by a relative entry, such as C:\;Program Files\Foo, reported as one entry
          when the joined path (C:\Program Files\Foo) is an existing directory and holds no
          %VAR% reference (see NOTES)
        - An empty or blank entry
        - A duplicate of an earlier entry (case-insensitive)
        - A directory that does not exist (a bare drive root such as C:\ is never reported)
        - A quoted entry holding semicolons that is not a directory (stray quotes around entries)
        - A %VAR% reference that this process can expand but Windows did not: the process
          PATH is already expanded, so it came from a REG_SZ PATH, where Windows does not
          expand %VAR%. Reported with SuggestedEntry the entry unchanged, since the fix is
          to make that PATH REG_EXPAND_SZ, even when a folder with the literal %VAR% name
          exists (it is never checked for existence). An entry whose variable is not set
          is checked as written, like any other

        Outputs one object per malformed entry with Entry, Issue and SuggestedEntry
        properties. When an entry has several issues, the last check that matched wins,
        in the order listed above, except that a duplicate copy of an unexpanded %VAR%
        entry stays a Duplicate entry (Delete): the first copy carries the %VAR% report.
        SuggestedEntry is either a corrected entry or the word Delete. For a split drive
        root, Entry is the pair as it appears in PATH and SuggestedEntry the joined path, or
        Delete when the joined path repeats an earlier entry. Repair-PathEntry handles that
        case as two questions, the join and then a Duplicates removal, so with -FixTypes
        IncorrectSemicolons alone the duplicate stays. Reads only; changes nothing.

        Formerly Get-MalformedPathEntries in Scripts/System/Get-MalformedPathEntries-Sensor.ps1;
        that name is kept as an alias, and the script is now a thin wrapper around this function.

    .EXAMPLE
        Get-MalformedPathEntry

        Lists the malformed entries of the current PATH.

    .EXAMPLE
        Get-MalformedPathEntry | ForEach-Object { "$($_.Entry)|$($_.Issue)|$($_.SuggestedEntry)" }

        Formats the result as pipe-delimited lines, as the sensor script does.

    .NOTES
        A drive root followed by a rooted entry (C:\;D:\Tools), a quoted one, or a join that
        is not an existing directory is not a split entry. Nor is a join holding a %VAR%
        reference: the process PATH is already expanded, so that %VAR% is one Windows did
        not expand, and the pair follows the rule Repair-PathEntry uses in a REG_SZ PATH (no
        join). The entry after the drive root is then checked on its own, as listed above.
        Part of the PathRepair module.
    #>
    [CmdletBinding()]
    [Alias('Get-MalformedPathEntries')]
    param ()

    $pathRaw = Read-EnvironmentVariable -Name 'PATH'
    if ([string]::IsNullOrEmpty($pathRaw)) {
        Write-Error 'An error occurred while analyzing the PATH variable: The PATH environment variable is empty or not set.'
        return
    }

    # Remove leading/trailing semicolons and split on semicolons outside quotes
    $pathEntries = @(Split-PathValue -Value $pathRaw.Trim(';'))
    $seenPaths = @{}

    for ($index = 0; $index -lt $pathEntries.Count; $index++) {
        $entry = $pathEntries[$index]
        $suggestedEntry = $entry
        $issue = $null

        # The pair is reported once, and the entry after the drive root is not checked alone.
        if ($index + 1 -lt $pathEntries.Count) {
            $next = $pathEntries[$index + 1]
            $joined = Join-SplitDriveRoot -Entry $entry -Next $next
            # The process PATH is already expanded, so any %VAR% still in it is one Windows did
            # not expand: the REG_SZ rule of Repair-PathEntry applies, and such a pair is not
            # joined. Its halves are checked one by one below.
            if ($joined -and $joined -notmatch '%[^%;]+%' -and (Test-PathDirectory -Path $joined -Literal)) {
                if ($seenPaths.ContainsKey($joined)) {
                    [PSCustomObject]@{
                        Entry          = "$entry;$next"
                        Issue          = 'Incorrect semicolon after drive letter, joined entry is a duplicate'
                        SuggestedEntry = 'Delete'
                    }
                } else {
                    [PSCustomObject]@{
                        Entry          = "$entry;$next"
                        Issue          = 'Incorrect semicolon after drive letter, suggest joining'
                        SuggestedEntry = $joined
                    }
                    $seenPaths[$joined] = $true
                }
                $index++
                continue
            }
        }

        $quoteCount = ($entry -split '"').Count - 1
        if ($quoteCount % 2 -ne 0) {
            $suggestedEntry = $entry -replace '"', ''
            $issue = 'Unbalanced double-quotes, suggest removal'
        }

        if ([string]::IsNullOrWhiteSpace($entry)) {
            $issue = 'Empty or blank entry'
            $suggestedEntry = 'Delete'
        }

        $duplicate = $seenPaths.ContainsKey($entry)
        if ($duplicate) {
            $issue = 'Duplicate entry'
            $suggestedEntry = 'Delete'
        } else {
            $seenPaths[$entry] = $true
        }

        # The process PATH is already expanded, so a %VAR% left in it was never expanded by
        # Windows (a REG_SZ PATH). That is reported whether or not a folder of that literal
        # name exists, since the user means the expanded folder; a duplicate copy keeps its
        # Delete suggestion (the first copy carries this report). Every other entry is
        # checked as written.
        $unexpanded = $entry -match '%[^%;]+%' -and [System.Environment]::ExpandEnvironmentVariables($entry) -cne $entry
        if ($unexpanded) {
            if (-not $duplicate) {
                $issue = 'REG_SZ PATH: %VAR% is not expanded by Windows, suggest REG_EXPAND_SZ'
                $suggestedEntry = $entry
            }
        } elseif ($entry -notmatch '^("?)[A-Z]:\\\1$' -and -not (Test-PathDirectory -Path $entry -Literal)) {
            # A drive root, with or without a balanced pair of quotes, is exempt. -notmatch ignores case.
            $issue = 'Non-existent directory'
            $suggestedEntry = 'Delete'
            if ($entry -match '^"(?=[^"]*[^";\s])[^"]*;[^"]*"$') {
                $issue = 'Quoted span holds several entries, suggest removing the quotes'
                $suggestedEntry = @($entry.Trim('"') -split ';' | Where-Object { $_.Trim() }) -join ';'
            }
        }

        if ($issue) {
            [PSCustomObject]@{
                Entry          = $entry
                Issue          = $issue
                SuggestedEntry = $suggestedEntry
            }
        }
    }
}
