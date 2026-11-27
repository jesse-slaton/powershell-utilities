function Restore-PathFromBackup {
    <#
    .SYNOPSIS
        Restores the User PATH from the BADPATH backup variable.

    .DESCRIPTION
        Reads the User-scope BADPATH variable (the backup of the original User PATH that
        Repair-PathEntry writes before it changes anything), writes it back to the
        User-scope PATH, then deletes the User-scope PATH_FIX_DATE variable if it is set,
        and tells running programs about the change (WM_SETTINGCHANGE); a failed broadcast
        is only a warning, since PATH is restored by then. BADPATH itself is left in place. Writes an error and changes nothing when BADPATH is not set. Outputs
        nothing; -Verbose reports each step.

        BADPATH is read from HKCU\Environment as written, without expanding %VAR%
        references, and PATH is written with the registry value kind BADPATH has, so a
        REG_EXPAND_SZ backup comes back as REG_EXPAND_SZ with its %USERPROFILE%-style text.

        Both variables are read from the User scope, not from the current process, so a
        backup written earlier in the same session is found.

        Formerly Scripts/System/Restore-PathFromBackup.ps1.

    .EXAMPLE
        Restore-PathFromBackup

        Restores the User PATH from BADPATH and deletes PATH_FIX_DATE.

    .EXAMPLE
        Restore-PathFromBackup -WhatIf

        Shows what would be restored without changing anything.

    .NOTES
        Windows only: the User environment scope is stored in the registry. The new PATH
        applies to processes started afterwards, not to the current session. The Machine
        PATH is never read or changed.

        A BADPATH written by the old Scripts/System/Repair-PathEntries.ps1 holds the merged
        Machine and User PATH of that process, not the User PATH, so restoring it copies
        Machine entries into the User PATH. Repair-PathEntry marks its own backups with
        the User-scope variable BADPATH_SCOPE=User|<PATH_FIX_DATE>, and this function warns
        unless that marker names the current PATH_FIX_DATE. The old script rewrites
        PATH_FIX_DATE without touching the marker, so a backup it wrote after a newer
        repair still warns. It does not back up the User PATH it overwrites, and every
        applying repair replaces BADPATH, so only one generation is kept.
        Part of the PathRepair module.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param ()

    $backup = Read-UserEnvironmentValue -Name 'BADPATH'
    $badPath = $backup.Value
    if ([string]::IsNullOrEmpty($badPath)) {
        Write-Error 'The BADPATH environment variable does not exist or is empty.'
        return
    }

    $fixDate = (Read-UserEnvironmentValue -Name 'PATH_FIX_DATE').Value
    if ((Read-UserEnvironmentValue -Name 'BADPATH_SCOPE').Value -ne "User|$fixDate") {
        Write-Warning 'BADPATH has no BADPATH_SCOPE=User marker for the current PATH_FIX_DATE, so the old Repair-PathEntries.ps1 may have written it with the merged Machine and User PATH, or this backup was already restored. Check BADPATH before restoring it.'
    }

    if (-not $PSCmdlet.ShouldProcess('User PATH', "Restore from BADPATH ($badPath)")) {
        return
    }

    Write-UserEnvironmentValue -Name 'PATH' -Value $badPath -Kind $backup.Kind
    Write-Verbose 'PATH has been successfully restored from BADPATH.'

    if ($fixDate) {
        Write-UserEnvironmentValue -Name 'PATH_FIX_DATE' -Value $null
        Write-Verbose 'PATH_FIX_DATE has been successfully deleted.'
    } else {
        Write-Verbose 'PATH_FIX_DATE does not exist or has already been deleted.'
    }
    Send-EnvironmentChange
}
