<#
.SYNOPSIS
    Starts the Symantec Endpoint Protection client with smc.exe -start.

.DESCRIPTION
    For each of C:\Program Files (x86)\Symantec\Symantec Endpoint Protection and
    C:\Program Files\Symantec\Symantec Endpoint Protection that exists, runs smc.exe
    from that folder with a hard-coded client password (-p) and -start, in a hidden
    window, and waits for it to exit. Outputs the process object of each run
    (-PassThru). Changes system state.

.EXAMPLE
    .\StartSMC.ps1

    Starts the SEP client. stopSMC.ps1 stops it.

.NOTES
    Requires administrator rights and the Symantec Endpoint Protection client. The
    password in the script must match the client's configured password for smc.exe
    to accept the command.
#>
$Paths = @("C:\Program Files (x86)\Symantec\Symantec Endpoint Protection","C:\Program Files\Symantec\Symantec Endpoint Protection")
Foreach ($Path in $Paths) {
    If (Test-path -Path $path)
        {
            Start-Process -FilePath "$path\smc.exe" -ArgumentList "-p Contoso!T -start" -Wait -WindowStyle Hidden -PassThru
        }
}