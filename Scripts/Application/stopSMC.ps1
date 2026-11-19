<#
.SYNOPSIS
    Disables and stops the Symantec Endpoint Protection client with smc.exe.

.DESCRIPTION
    For each of C:\Program Files (x86)\Symantec\Symantec Endpoint Protection and
    C:\Program Files\Symantec\Symantec Endpoint Protection that exists, runs smc.exe
    from that folder twice, each time with a hard-coded client password (-p), in a
    hidden window, waiting for each to exit: first with '-disable -wss', then with
    '-stop'. Outputs the process object of each run (-PassThru). Changes system state.

    The password is in a double-quoted string that contains '$$', which PowerShell
    expands as the $$ automatic variable, so the password passed to smc.exe is not the
    literal text in the script.

.EXAMPLE
    .\stopSMC.ps1

    Disables and stops the SEP client. StartSMC.ps1 starts it again.

.NOTES
    Requires administrator rights and the Symantec Endpoint Protection client. The
    password passed must match the client's configured password for smc.exe to accept
    the commands.
#>
$Paths = @("C:\Program Files (x86)\Symantec\Symantec Endpoint Protection", "C:\Program Files\Symantec\Symantec Endpoint Protection")
Foreach ($Path in $Paths) {
    If (Test-path -Path $path) {
        Start-Process -FilePath "$path\smc.exe" -ArgumentList "-p Pa$$4SEP! -disable -wss" -Wait -WindowStyle Hidden -PassThru
        Start-Process -FilePath "$path\smc.exe" -ArgumentList "-p Pa$$4SEP! -stop" -Wait -WindowStyle Hidden -PassThru
    }
}