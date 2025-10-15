$ConfigFile = 'C:\Program Files\Avaya\Avaya Agent\config\config-spec.xml'
$SHA256Hash = 'bb28533ee5e3950a7eef4013ddca693519f5c6cebe8bdb5cc5df19f5c3287294'
$ReturnCode = 99
If (Test-Path -Path "$ConfigFile") {
    If ((Get-FileHash -Path $Configfile).Hash -match $SHA256Hash) {
        $ReturnCode = 0
    }
}
Exit $ReturnCode