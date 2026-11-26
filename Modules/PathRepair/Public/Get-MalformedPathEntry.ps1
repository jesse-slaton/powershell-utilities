function Get-MalformedPathEntry {
    <#
    .SYNOPSIS
        Reports malformed entries in the PATH environment variable of the current process.

    .DESCRIPTION
        Splits the current process PATH (the merged Machine and User PATH) on semicolons
        outside double quotes (on every semicolon when the quotes are unbalanced) and checks
        each entry for:
        - Unbalanced double quotes
        - A semicolon directly after the drive root (C:\;...)
        - An empty or blank entry
        - A duplicate of an earlier entry (case-insensitive)
        - A directory that does not exist (a bare drive root such as C:\ is never reported)
        - A quoted entry holding semicolons that is not a directory (stray quotes around entries)
        - A %VAR% reference that this process can expand but Windows did not: the process
          PATH is already expanded, so it came from a REG_SZ PATH, where Windows does not
          expand %VAR%. Reported with SuggestedEntry the entry unchanged, since the fix is
          to make that PATH REG_EXPAND_SZ. An entry whose variable is not set is checked
          as written, like any other

        Outputs one object per malformed entry with Entry, Issue and SuggestedEntry
        properties. When an entry has several issues, the last check that matched wins.
        SuggestedEntry is either a corrected entry or the word Delete. Reads only;
        changes nothing.

        Formerly Get-MalformedPathEntries in Scripts/System/Get-MalformedPathEntries-Sensor.ps1;
        that name is kept as an alias, and the script is now a thin wrapper around this function.

    .EXAMPLE
        Get-MalformedPathEntry

        Lists the malformed entries of the current PATH.

    .EXAMPLE
        Get-MalformedPathEntry | ForEach-Object { "$($_.Entry)|$($_.Issue)|$($_.SuggestedEntry)" }

        Formats the result as pipe-delimited lines, as the sensor script does.

    .NOTES
        Known limitation: the semicolon-after-drive-root check never matches. PATH is split
        first, so 'C:\;dir' arrives as two entries, C:\ and dir, and the check sees each
        alone. Checking neighbouring entries as a pair would be a new feature, tracked in
        issue #162. Part of the PathRepair module.
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

    foreach ($entry in $pathEntries) {
        $suggestedEntry = $entry
        $issue = $null

        $quoteCount = ($entry -split '"').Count - 1
        if ($quoteCount % 2 -ne 0) {
            $suggestedEntry = $entry -replace '"', ''
            $issue = 'Unbalanced double-quotes, suggest removal'
        }

        if ($entry -match '^[A-Z]:\\;') {
            $correctedPath = $entry -replace ':\\;', ':\'
            if (Test-PathDirectory -Path $correctedPath) {
                $suggestedEntry = $correctedPath
                $issue = 'Incorrect semicolon after drive letter, suggest valid path'
            } else {
                $suggestedEntry = 'Delete'
                $issue = 'Incorrect semicolon after drive letter, no valid path found'
            }
        }

        if ([string]::IsNullOrWhiteSpace($entry)) {
            $issue = 'Empty or blank entry'
            $suggestedEntry = 'Delete'
        }

        if ($seenPaths.ContainsKey($entry)) {
            $issue = 'Duplicate entry'
            $suggestedEntry = 'Delete'
        } else {
            $seenPaths[$entry] = $true
        }

        # The process PATH is already expanded, so a %VAR% left in it was never expanded by
        # Windows (a REG_SZ PATH), and every entry is checked as written.
        $unexpanded = $entry -match '%[^%;]+%' -and [System.Environment]::ExpandEnvironmentVariables($entry) -cne $entry
        # A drive root, with or without a balanced pair of quotes. -notmatch ignores case.
        if ($entry -notmatch '^("?)[A-Z]:\\\1$' -and -not (Test-PathDirectory -Path $entry -Literal)) {
            if ($unexpanded) {
                $issue = 'REG_SZ PATH: %VAR% is not expanded by Windows, suggest REG_EXPAND_SZ'
                $suggestedEntry = $entry
            } else {
                $issue = 'Non-existent directory'
                $suggestedEntry = 'Delete'
                if ($entry -match '^"(?=[^"]*[^";\s])[^"]*;[^"]*"$') {
                    $issue = 'Quoted span holds several entries, suggest removing the quotes'
                    $suggestedEntry = @($entry.Trim('"') -split ';' | Where-Object { $_.Trim() }) -join ';'
                }
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
