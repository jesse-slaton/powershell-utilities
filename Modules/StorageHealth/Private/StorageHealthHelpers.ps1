# Thin wrappers around external tools. Every native command in StorageHealth goes through
# these functions so tests can mock them and so a failure is reported in one place.

function Invoke-VssAdmin {
    <#
    .SYNOPSIS
        Runs vssadmin.exe with the given arguments and returns its output.

    .DESCRIPTION
        Runs vssadmin.exe from PATH and returns its output lines. A non-zero exit code, or an
        output line that starts with "Error:" (Microsoft does not document vssadmin's exit
        codes), writes a non-terminating error that includes the arguments and the output.
        Private to StorageHealth.

    .PARAMETER ArgumentList
        The arguments passed to vssadmin.exe, one per element.

    .EXAMPLE
        Invoke-VssAdmin -ArgumentList 'list', 'shadowstorage'

        Returns the shadow storage associations of every volume.

    .EXAMPLE
        Invoke-VssAdmin -ArgumentList 'resize', 'ShadowStorage', '/For=C:', '/On=C:', '/MaxSize=10%'

        Caps the shadow storage of C: at 10 percent of the drive.

    .NOTES
        Windows only. Most vssadmin commands require administrator rights.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList
    )

    $output = @(& vssadmin @ArgumentList)
    # vssadmin exit codes are undocumented, so an "Error:" line also counts as failure.
    if ($LASTEXITCODE -ne 0 -or @($output -match '^\s*Error:').Count -gt 0) {
        Write-Error -Message ("vssadmin.exe {0} failed with exit code {1}: {2}" -f ($ArgumentList -join ' '), $LASTEXITCODE, ($output -join ' '))
        return
    }
    $output
}
