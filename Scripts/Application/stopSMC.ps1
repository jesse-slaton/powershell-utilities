param(
    # SEP client password passed to smc.exe -p. Not stored in this script.
    [Parameter(Mandatory)]
    [SecureString]$Password
)
$PlainPassword = (New-Object System.Net.NetworkCredential('', $Password)).Password
$Paths = @("C:\Program Files (x86)\Symantec\Symantec Endpoint Protection", "C:\Program Files\Symantec\Symantec Endpoint Protection")
Foreach ($Path in $Paths) {
    If (Test-path -Path $path) {
        Start-Process -FilePath "$path\smc.exe" -ArgumentList "-p $PlainPassword -disable -wss" -Wait -WindowStyle Hidden -PassThru
        Start-Process -FilePath "$path\smc.exe" -ArgumentList "-p $PlainPassword -stop" -Wait -WindowStyle Hidden -PassThru
    }
}