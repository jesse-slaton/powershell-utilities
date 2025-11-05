$Paths = @("C:\Program Files (x86)\Symantec\Symantec Endpoint Protection", "C:\Program Files\Symantec\Symantec Endpoint Protection")
Foreach ($Path in $Paths) {
    If (Test-path -Path $path) {
        Start-Process -FilePath "$path\smc.exe" -ArgumentList "-p Pa$$4SEP! -disable -wss" -Wait -WindowStyle Hidden -PassThru
        Start-Process -FilePath "$path\smc.exe" -ArgumentList "-p Pa$$4SEP! -stop" -Wait -WindowStyle Hidden -PassThru
    }
}