<#
.SYNOPSIS
    Lists non-empty AF client install logs (*afc*.wil) in C:\DesktopSupportTools\Logs.

.DESCRIPTION
    Outputs the files in C:\DesktopSupportTools\Logs on the local computer whose name
    matches *afc*.wil and whose size is greater than zero (FileInfo objects).

    Before that, for the hard-coded computer 'VDI-X0001' it pings the computer with
    Test-NetConnection and, if it answers, reads the matching files from
    \\<ComputerName>\c$\DesktopSupportTools\Logs into a variable. That remote list is
    not output or used. Read-only.

.EXAMPLE
    .\getfailedinstalllogs.ps1

    Lists the local non-empty *afc*.wil logs.

.NOTES
    Test-NetConnection needs the NetTCPIP module (Windows 8 / Server 2012 or later). The
    remote check needs network access to the computer and rights to its c$ admin share
    (normally administrator). The computer name is hard-coded in the script.
#>
$logpath = "DesktopSupportTools\Logs"
$computers = 'VDI-X0001'
#$computers = Import-CSV -Path "$env:USERPROFILE\Downloads\afclientPCs.csv"

Foreach ($Computer in $computers) {
    If ((Test-NetConnection -ComputerName "$computers").PingSucceeded -eq $True) {
        $AFClientLogfiles = Get-ChildItem -Path "\\$computer\c$\$logpath" | Where-Object {$_.Name -like '*afc*.wil'}
    }
}

Get-ChildItem -Path C:\DesktopSupportTools\Logs\ | Where-Object {$_.Name -like '*afc*.wil' -and $_.Length -gt 0 }