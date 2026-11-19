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