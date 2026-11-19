<#
.SYNOPSIS
    Disables and stops the Symantec Endpoint Protection client with smc.exe.

.DESCRIPTION
    For each of C:\Program Files (x86)\Symantec\Symantec Endpoint Protection and
    C:\Program Files\Symantec\Symantec Endpoint Protection that exists, runs smc.exe
    from that folder twice, each time with the client password (-p), in a
    hidden window, waiting for each to exit: first with '-disable -wss', then with
    '-stop'. Outputs the process object of each run (-PassThru). Changes system state.

.PARAMETER Password
    The SEP client password, as a SecureString. Mandatory; if you omit it, PowerShell
    prompts for it. The script converts it to plain text, wraps it in double quotes
    (escaping any embedded quotes and the backslashes before them) and passes it to
    smc.exe -p. The password is not stored in the script.

.EXAMPLE
    .\stopSMC.ps1

    PowerShell prompts for Password. Disables and stops the SEP client. StartSMC.ps1
    starts it again.

.EXAMPLE
    $Pw = Read-Host -AsSecureString -Prompt 'SEP client password'
    .\stopSMC.ps1 -Password $Pw

    Reads the password once into a SecureString and passes it to the script.

.NOTES
    Requires administrator rights and the Symantec Endpoint Protection client. The
    password must match the client's configured password for smc.exe to accept the
    commands.
#>
param(
    # SEP client password passed to smc.exe -p. Not stored in this script.
    [Parameter(Mandatory)]
    [SecureString]$Password
)
$PlainPassword = (New-Object System.Net.NetworkCredential('', $Password)).Password
# Quote the password for the Windows command line (CommandLineToArgvW rules): wrap it in
# double quotes, escape embedded quotes, and double any backslashes that precede a quote,
# so passwords with spaces or quote characters reach smc.exe unchanged.
$QuotedPassword = '"' + (($PlainPassword -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
$Paths = @("C:\Program Files (x86)\Symantec\Symantec Endpoint Protection", "C:\Program Files\Symantec\Symantec Endpoint Protection")
Foreach ($Path in $Paths) {
    If (Test-path -Path $path) {
        Start-Process -FilePath "$path\smc.exe" -ArgumentList "-p $QuotedPassword -disable -wss" -Wait -WindowStyle Hidden -PassThru
        Start-Process -FilePath "$path\smc.exe" -ArgumentList "-p $QuotedPassword -stop" -Wait -WindowStyle Hidden -PassThru
    }
}