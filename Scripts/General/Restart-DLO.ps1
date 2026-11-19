<#
.SYNOPSIS
    Restarts the DLO (Desktop and Laptop Option) backup client and clears the current user's DLO settings.

.DESCRIPTION
    In order, the script:

    1. Stops the DLOChangeJournalSvc service with -Force. If that fails, it terminates
       every DLOChangeLogSvcu.exe process through Win32_Process.
    2. Terminates every DLOClientu.exe process (for all users) through Win32_Process.
    3. Deletes every DLO folder one level under the current user's
       $env:LOCALAPPDATA (the path $env:LOCALAPPDATA\*\DLO), recursively and with
       -Force.
    4. Starts DLOChangeJournalSvc.
    5. Starts DloClientu.exe with the argument -u, from the first match of
       $env:SystemDrive\Program Files*\*\*DLO\DLO\DloClientu.exe after sorting by
       VersionInfo.

    Terminate calls write their result objects to the output.

.EXAMPLE
    .\Restart-DLO.ps1

    Run from an elevated prompt in the affected user's session: resets that user's
    DLO settings and restarts DLO.

.NOTES
    Requires administrator rights (stops a service and other users' processes) and the
    DLO client installed (Get-Service writes an error if DLOChangeJournalSvc does not
    exist).
    Deletes user settings, so run it as the user whose DLO profile should be reset.
    Uses the CIM cmdlets; runs on Windows PowerShell 5.1 and PowerShell 7.
#>

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
    $Processes = Get-CimInstance -ClassName Win32_Process -Filter "name='$ProcessName'"
    foreach ($process in $processes) {
        Invoke-CimMethod -InputObject $process -MethodName Terminate
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