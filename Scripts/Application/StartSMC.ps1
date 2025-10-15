$Paths = @("C:\Program Files (x86)\Symantec\Symantec Endpoint Protection","C:\Program Files\Symantec\Symantec Endpoint Protection")
Foreach ($Path in $Paths) {
    If (Test-path -Path $path)
        {
            Start-Process -FilePath "$path\smc.exe" -ArgumentList "-p Contoso!T -start" -Wait -WindowStyle Hidden -PassThru
        }
}