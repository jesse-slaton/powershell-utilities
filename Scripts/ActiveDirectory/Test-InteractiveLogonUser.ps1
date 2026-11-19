<#
.SYNOPSIS
    Defines the Test-InteractiveLogonUser function, which reports whether a user appears to be logged on.

.DESCRIPTION
    Running this script only defines the Test-InteractiveLogonUser function; nothing is
    checked and nothing is output. Dot-source it to use the function.

    Test-InteractiveLogonUser calls Test-Process -ProcessName <Process> and outputs
    $true when that returns a true value (assuming an interactive user is logged on
    while the process, explorer by default, is running) and $false otherwise. The
    function takes one parameter, Process (process name, default 'explorer').

    Test-Process is not a built-in cmdlet and is not defined in this script or
    elsewhere in this repository, so unless a Test-Process command is already loaded the
    call fails with a command-not-found error. Read-only.

.EXAMPLE
    . .\Test-InteractiveLogonUser.ps1
    Test-InteractiveLogonUser -Verbose

    Defines the function, then checks for explorer processes.

.NOTES
    Needs a Test-Process command to be available in the session (see DESCRIPTION).
    Otherwise None.
#>


function Test-InteractiveLogonUser {
    <#
    .SYNOPSIS
        Reports whether an interactive user appears to be logged on.

    .DESCRIPTION
        Calls Test-Process -ProcessName <Process> and outputs $true when it returns a
        true value, $false otherwise. Test-Process is not a built-in cmdlet and is not
        defined in this repository; it must already be loaded in the session.

    .PARAMETER Process
        Name of the process whose presence counts as an interactive logon. Defaults to
        explorer. The verbose messages always say "explorer".

    .EXAMPLE
        Test-InteractiveLogonUser

        Outputs $true if an explorer process is found, otherwise $false.

    .EXAMPLE
        Test-InteractiveLogonUser -Process 'explorer' -Verbose

        Same check, with a verbose message describing the result.

    .NOTES
        Requires a Test-Process command in the session.
    #>
    [cmdletbinding()]
    param (
        $Process = 'explorer'
    )
    if (Test-Process -ProcessName $Process) {
        Write-Verbose "Found explorer process(es). Assuming interactive user(s) logged in."
        Write-Output $true
    }
    else {
        Write-Verbose "No explorer processes found. Assuming no interactive user logged in."
        Write-Output $false
    }
}