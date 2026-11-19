<#
.SYNOPSIS
    Removes the Windows Update (WSUS) policy settings and restarts the Windows Update service.

.DESCRIPTION
    Stops the wuauserv service (the script stops if this fails), removes the WUServer and
    WUStatusServer values, then deletes the whole
    HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate key recursively. That also
    removes every other Windows Update policy under it, including the AU subkey. It then
    sets wuauserv to Automatic startup and starts it. Produces no output on success.

    If the settings come from Group Policy, the next policy refresh writes them back.

.EXAMPLE
    .\RemoveWSUSSettings.ps1

    Points the computer back at Windows Update instead of the configured WSUS server.

.NOTES
    Requires administrator rights. Changes system configuration.
#>

# Stop the Windows Update service
Stop-Service -Name wuauserv -ErrorAction Stop

# Delete the registry keys
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "WUServer" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "WUStatusServer" -ErrorAction SilentlyContinue
Remove-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Recurse -ErrorAction SilentlyContinue

# Reset the Windows Update service
Set-Service -Name wuauserv -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service -Name wuauserv -ErrorAction Stop