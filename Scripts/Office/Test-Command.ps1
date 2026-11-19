<#
.SYNOPSIS
    Defines Test-Command, which reports whether a command is available in the session.

.DESCRIPTION
    Running the script only defines the Test-Command function; it writes no output.
    Dot-source the script, then call the function.

    Test-Command -Name <name> runs Get-Command -Name <name> -ErrorAction Stop and outputs
    $true when it returns a command. When Get-Command throws, it writes the warning
    "Unable to find command <name>" and outputs $false. Read-only.

.EXAMPLE
    . .\Test-Command.ps1
    Test-Command -Name 'Get-CimInstance'

    True

.EXAMPLE
    . .\Test-Command.ps1
    if (-not (Test-Command -Name 'Get-BitLockerVolume')) { 'BitLocker module not available' }

    Uses the result to decide whether a command can be called.

.NOTES
    None.
#>


function Test-Command {
    <#
    .SYNOPSIS
        Reports whether a command is available in the session.

    .DESCRIPTION
        Runs Get-Command -Name <Name> -ErrorAction Stop and outputs $true when it returns a
        command. When Get-Command throws, writes the warning "Unable to find command <Name>"
        and outputs $false.

    .PARAMETER Name
        Name of the command (cmdlet, function, alias or application) to look for.

    .EXAMPLE
        Test-Command -Name 'Get-CimInstance'

        True

    .EXAMPLE
        if (-not (Test-Command -Name 'Get-BitLockerVolume')) { 'BitLocker module not available' }

        Uses the result to decide whether a command can be called.

    .NOTES
        None.
    #>
    [CmdletBinding()]
    param (
        [string]$Name
    )
    try {
        $CommandExists = Get-Command -Name $Name -ErrorAction Stop
        if ($CommandExists) {
            Write-Output $true
        }
    }
    catch {
        Write-Warning "Unable to find command $Name"
        Write-Output $false
    }
}