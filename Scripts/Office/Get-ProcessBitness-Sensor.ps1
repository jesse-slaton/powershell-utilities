<#
.SYNOPSIS
    Defines Get-ProcessBitness, which reports whether running processes are 32-bit or 64-bit.

.DESCRIPTION
    Running the script only defines the Get-ProcessBitness function; it writes no output.
    Dot-source the script, together with the helper functions it calls, then call the
    function.

    Get-ProcessBitness -Process <name[]> first calls Get-Bitness. For each process name
    for which Test-Process returns true, it reads the loaded modules with
    Get-Process -Name <name> -Module. When Get-Bitness returned 'x64' it outputs 'x86'
    if wow64.dll is among the modules and 'x64' otherwise; when Get-Bitness returned
    'x86' it outputs 'x86'. For a name that Test-Process does not confirm it writes the
    warning "Unable to find process <name>". Read-only.

    Get-Bitness reports the bitness of the PowerShell process, so in 32-bit PowerShell
    every process is reported as 'x86'.

.EXAMPLE
    Import-Module .\Modules\OfficeC2R\OfficeC2R.psd1
    . .\Scripts\Office\Get-ProcessBitness-Sensor.ps1
    Get-ProcessBitness -Process 'OUTLOOK'

    Run from the repository root. Outputs x86 or x64 for Outlook, once Test-Process is
    also defined.

.EXAMPLE
    Get-ProcessBitness -Process 'OUTLOOK', 'EXCEL' -Verbose

    Outputs one value per running process name and writes why each was chosen.

.NOTES
    Requires the Get-Bitness function (OfficeC2R module) and a Test-Process function
    that accepts -Process; Test-Process is not defined in this repository. Run from
    64-bit PowerShell. Reading the modules of processes owned by other users needs
    administrator rights.
#>


function Get-ProcessBitness {
    <#
    .SYNOPSIS
        Reports whether running processes are 32-bit or 64-bit.

    .DESCRIPTION
        Calls Get-Bitness, then for each name that Test-Process confirms reads the process
        modules with Get-Process -Module. On x64 it outputs 'x86' when wow64.dll is loaded
        and 'x64' otherwise; on x86 it outputs 'x86'. For other names it writes the warning
        "Unable to find process <name>".

    .PARAMETER Process
        One or more process names, without the .exe extension (as used by
        Get-Process -Name). Required.

    .EXAMPLE
        Get-ProcessBitness -Process 'OUTLOOK'

        Outputs x86 or x64 for Outlook.

    .EXAMPLE
        Get-ProcessBitness -Process 'OUTLOOK', 'EXCEL' -Verbose

        Outputs one value per running process name and writes why each was chosen.

    .NOTES
        Requires the Get-Bitness and Test-Process functions to be loaded. Run from 64-bit
        PowerShell; reading other users' process modules needs administrator rights.
    #>
    [cmdletbinding()]
    param (
        [parameter(mandatory=$true)]
        [string[]]$Process
    )
    $Bitness = Get-Bitness
    foreach ($Proc in $Process) {
        if (Test-Process -Process $Proc) {
            $ProcessModules = Get-Process -Name $Proc -Module
            switch ($Bitness) {
                'x64' {
                    if ($ProcessModules.ModuleName -contains 'wow64.dll') {
                        Write-Verbose "Found wow64.dll module in $Proc - x86 process"
                        Write-Output 'x86'
                    }
                    else {
                        Write-Verbose "Did not find wow64.dll module in $Proc - x64 process"
                        Write-Output 'x64'
                    }
                }
                'x86' {
                    Write-Verbose 'x86 operating system detected.'
                    Write-Output 'x86'
                }
            }
        }
        else {
            Write-Warning "Unable to find process $Proc"
        }
    }
}