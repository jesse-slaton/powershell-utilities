param(
    # Folder used for the (commented-out) computer list CSV. Defaults to the current user's Downloads folder.
    [string]$LogSavePath = (Join-Path $env:USERPROFILE 'Downloads')
)

$logpath = "DesktopSupportTools\Logs"
$computers = 'VDI-X0001'
#$computers = Import-CSV -Path "$logsavepath\afclientPCs.csv"

Foreach ($Computer in $computers) {
    If ((Test-NetConnection -ComputerName "$computers").PingSucceeded -eq $True) {
        $AFClientLogfiles = Get-ChildItem -Path "\\$computer\c$\$logpath" | Where-Object {$_.Name -like '*afc*.wil'}
    }
}

Get-ChildItem -Path C:\DesktopSupportTools\Logs\ | Where-Object {$_.Name -like '*afc*.wil' -and Get-Content -$_.Name }