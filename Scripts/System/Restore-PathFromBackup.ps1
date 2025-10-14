<#
.SYNOPSIS
    Restores the PATH environment variable from the BADPATH backup.

.DESCRIPTION
    This script restores the PATH environment variable from the backed-up BADPATH environment variable. After the PATH is restored successfully, it deletes the PATH_FIX_DATE environment variable.

.EXAMPLE
    Restore-PathFromBackup
    Restores the original PATH from BADPATH and deletes the PATH_FIX_DATE variable.

#>

function Restore-PathFromBackup {
    [CmdletBinding()]
    param ()

    try {
        # Get the BADPATH variable (the backup of the original PATH)
        $badPath = [System.Environment]::GetEnvironmentVariable('BADPATH')

        if (-not $badPath) {
            throw "The BADPATH environment variable does not exist or is empty."
        }

        # Restore the PATH variable from BADPATH
        [System.Environment]::SetEnvironmentVariable('PATH', $badPath, [System.EnvironmentVariableTarget]::User)

        Write-Host "PATH has been successfully restored from BADPATH."

        # Delete the PATH_FIX_DATE variable if it exists
        $pathFixDate = [System.Environment]::GetEnvironmentVariable('PATH_FIX_DATE')

        if ($pathFixDate) {
            [System.Environment]::SetEnvironmentVariable('PATH_FIX_DATE', $null, [System.EnvironmentVariableTarget]::User)
            Write-Host "PATH_FIX_DATE has been successfully deleted."
        } else {
            Write-Host "PATH_FIX_DATE does not exist or has already been deleted."
        }

    } catch {
        Write-Error "An error occurred: $_"
    }
}

# Run the function to restore the PATH
Restore-PathFromBackup
