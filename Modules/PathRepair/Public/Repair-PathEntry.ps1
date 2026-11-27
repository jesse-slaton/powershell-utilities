function Repair-PathEntry {
    <#
    .SYNOPSIS
        Repairs malformed entries in the User PATH, locally or on a remote computer.

    .DESCRIPTION
        Reads the User-scope PATH, works out which entries to fix or remove for the
        selected issue types, and asks ShouldProcess about each change, so -WhatIf lists
        every change without writing anything and -Confirm (or -Prompt) asks about each
        one. A declined change leaves that entry as it is. When at least one change is
        approved, re-reads the User PATH and, only if its text and its registry value kind
        are both unchanged since the preview, saves it to the User-scope BADPATH variable (undo with Restore-PathFromBackup),
        sets PATH_FIX_DATE to the current time and BADPATH_SCOPE to User|<that time>
        (the marker Restore-PathFromBackup checks), and writes the
        User PATH with exactly the approved changes. It writes nothing, and reports an
        error, when the User PATH text or value kind changed in between or when the repair would leave it
        with no non-blank entry. The Machine PATH is never read or changed.

        The User PATH and BADPATH are read from HKCU\Environment as written, without
        expanding %VAR% references, and written back with the registry value kind PATH had,
        so a REG_EXPAND_SZ PATH keeps its kind and its %USERPROFILE%-style entries. In a
        REG_EXPAND_SZ PATH only the directory checks expand them, for the check alone, and
        an entry whose variable this process cannot expand is never removed as
        non-existent. An entry whose variable expands to several folders (a value holding
        ';') is removed as non-existent only when none of them exists. Duplicates compares entries as written, so %USERPROFILE%\bin and its
        expanded form are both kept.

        Windows does not expand %VAR% in a REG_SZ PATH, so there such an entry is checked
        as written. It is never removed as non-existent (the expanded folder is what was
        meant): it is kept, and a warning names it and suggests making PATH REG_EXPAND_SZ,
        even when a folder with that literal name exists. The value kind is never changed.

        After a write, running programs are told about the change (a WM_SETTINGCHANGE
        "Environment" broadcast). The write is already complete then, so a failed
        broadcast is only a warning and the result still has Applied $true.

        Issue types:
        - UnbalancedQuotes: removes every double quote from an entry with an odd number
        - IncorrectSemicolons: C:\;dir becomes C:\dir when that directory exists (matches nothing; see NOTES)
        - Duplicates: removes later copies of an entry (case-insensitive)
        - BlankEntries: removes empty and blank entries
        - NonExistentPaths: removes entries that are not an existing directory (a bare drive root is kept),
          but unquotes a quoted entry holding semicolons (stray quotes around several entries)

        Outputs one object with ComputerName, OriginalPath, NewPath, Changes (Entry,
        NewEntry, which is $null for a removal, and Reason; only the approved changes once
        applied) and Applied. With nothing approved, the object describes the proposed
        repair and Applied is $false.

        Formerly Repair-PathEntries in Scripts/System/Repair-PathEntries.ps1; that name is
        kept as an alias, and so is the old -Credentials parameter name.

    .PARAMETER FixTypes
        Issue types to fix. Defaults to all five.

    .PARAMETER ComputerName
        Remote computer to repair through PowerShell remoting (Invoke-Command). Omit it to
        repair this computer. The module does not need to be installed there. A remote
        session cannot reach network shares or mapped drives (the second hop), so their
        entries look missing: UNC (\\server\share) entries, written out or reached through
        a %VAR% that expands to one, are never removed as non-existent remotely, but
        mapped-drive entries are. Run with -WhatIf first.

    .PARAMETER Credential
        Credential for the remote connection. Used only with ComputerName.

    .PARAMETER Prompt
        Asks for confirmation before each change, the same as -Confirm.

    .EXAMPLE
        Repair-PathEntry -FixTypes Duplicates, NonExistentPaths -WhatIf

        Lists the duplicate and missing-directory entries it would remove, changing nothing.

    .EXAMPLE
        Repair-PathEntry -FixTypes UnbalancedQuotes -ComputerName PC01 -Credential (Get-Credential)

        Removes unbalanced quotes from the User PATH of the connecting user on PC01.

    .NOTES
        Windows only: the User environment scope is stored in the registry. The repaired
        PATH applies to processes started afterwards. The remote form needs PowerShell
        remoting (WinRM) enabled on the target, and it repairs the User PATH of the
        account that connects.

        On a remote computer the broadcast reaches only the remoting session, so the
        user's own desktop sees the repaired PATH after the next sign-in.

        Known limitation: IncorrectSemicolons never matches. PATH is split first, so
        'C:\;dir' arrives as two entries, C:\ and dir, and the check sees each alone.
        Checking neighbouring entries as a pair would be a new feature, tracked in issue
        #162. Part of the PathRepair module.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [Alias('Repair-PathEntries')]
    param (
        [ValidateSet('UnbalancedQuotes', 'IncorrectSemicolons', 'Duplicates', 'BlankEntries', 'NonExistentPaths')]
        [string[]]$FixTypes = @('UnbalancedQuotes', 'IncorrectSemicolons', 'Duplicates', 'BlankEntries', 'NonExistentPaths'),

        [string]$ComputerName,

        [Alias('Credentials')]
        [pscredential]$Credential,

        [switch]$Prompt
    )

    if ($Prompt) {
        # ShouldProcess prompts when ConfirmImpact (Medium) is at or above $ConfirmPreference.
        $ConfirmPreference = 'Low'
    }

    $target = 'User PATH on this computer'
    if ($ComputerName) {
        $target = "User PATH on $ComputerName"
    }

    $targetParams = @{ FixTypes = $FixTypes }
    if ($ComputerName) {
        $targetParams['ComputerName'] = $ComputerName
        $targetParams['Credential'] = $Credential
    }

    try {
        $preview = Invoke-PathRepairTarget @targetParams
    } catch {
        Write-Error "An error occurred while processing the $target`: $($_.Exception.Message)"
        return
    }

    $selection = Select-ApprovedPathChange -Cmdlet $PSCmdlet -Target $target -Plan $preview
    $changes = @($selection.Changes)
    $newPath = $selection.NewPath
    $applied = $changes.Count -gt 0
    if ($applied) {
        try {
            $null = Invoke-PathRepairTarget @targetParams -Apply -OriginalPath $preview.OriginalPath -OriginalKind $preview.OriginalKind -NewPath $newPath
        } catch {
            Write-Error "An error occurred while processing the $target`: $($_.Exception.Message)"
            return
        }
        Write-Verbose "Original $target backed up to BADPATH; new PATH applied."
    } else {
        $changes = @($preview.Changes)
        $newPath = $preview.NewPath
    }

    [pscustomobject]@{
        ComputerName = $preview.ComputerName
        OriginalPath = $preview.OriginalPath
        NewPath      = $newPath
        Changes      = @($changes | Select-Object -Property Entry, NewEntry, Reason)
        Applied      = $applied
    }
}
