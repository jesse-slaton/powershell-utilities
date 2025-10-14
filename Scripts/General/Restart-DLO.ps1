$DLOClientEXE = 'DLOClientu.exe'
$DLOService = Get-Service -Name DLOChangeJournalSvc
$DLOServiceEXE = 'DLOChangeLogSvcu.exe'
$DLOClient = Get-Item "$env:Systemdrive\Program Files*\*\*DLO\DLO\DloClientu.exe" | `
    Sort-Object VersionInfo -Descending | Select-Object -First 1
$DLOClientArguments = '-u'

Function EXTERMINATE {
    [cmdletbinding()]
    param(
        $ProcessName
    )
    $Processes = Get-WmiObject -Class Win32_Process -Filter "name='$ProcessName'"
    foreach ($process in $processes) {
        $process.terminate()
    }
}

#Stop DLO Service
Try {
    $DLOService | Stop-Service -Force -ErrorAction Stop
}
Catch {
    EXTERMINATE -ProcessName $DLOServiceEXE
}

#Stop DLO Client
EXTERMINATE -ProcessName $DLOClientEXE

#Clean Out DLO User Settings
Get-Item -Path "\\?\$Env:LOCALAPPDATA\*\DLO" | Remove-Item -Recurse -Force

#Start DLO Service
$DLOService | Start-Service

#Start DLO Client
Start-Process -FilePath $DLOClient -ArgumentList $DLOClientArguments