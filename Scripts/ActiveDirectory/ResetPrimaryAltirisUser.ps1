<#
.SYNOPSIS
    Clears the Altiris Agent's recorded primary user and sends a new basic inventory.

.DESCRIPTION
    Stops the Altiris Agent service (AeXNSClient), then:

    - deletes the PrimaryUser value under HKLM:\SOFTWARE\Altiris\Altiris Agent\Inventory,
      or writes a warning if reading that value fails with "Property PrimaryUser does
      not exist" (any other read error, such as a missing key, still leads to a
      Remove-ItemProperty attempt)
    - deletes $env:ProgramFiles\Altiris\Altiris Agent\AeXUserMonitorLog.xml, or writes a
      warning if the file is not found

    It then starts the AeXNSClient service again and calls SendBasicInventory() on the
    AltirisAgent_Client WMI class so the agent reports to the Notification Server. Errors
    stopping or starting the service are suppressed. Changes system state.

.EXAMPLE
    .\ResetPrimaryAltirisUser.ps1

    Resets the primary user so the agent recalculates it, then sends basic inventory.

.NOTES
    Requires administrator rights, the Altiris (Symantec Management) Agent, and Windows
    PowerShell 5.1 (it uses Get-WmiObject, which is not available in PowerShell 7). The
    warning text check is in English, so on other display languages a missing value
    produces an error instead of a warning.
#>
$AgentInventoryRegKey = 'HKLM:\SOFTWARE\Altiris\Altiris Agent\Inventory'
$PrimaryUserRegValue = 'PrimaryUser'
$LogLocation = "$env:ProgramFiles\Altiris\Altiris Agent\AeXUserMonitorLog.xml"
$AgentUtil = "$env:ProgramFiles\Altiris\Altiris Agent\AeXAgentUtil.exe"
$AltirisAgentClientClass = Get-WmiObject -Class 'AltirisAgent_Client' -List -Namespace 'root\cimv2'

Get-Service AeXNSClient -ErrorAction SilentlyContinue | Stop-Service -ErrorAction SilentlyContinue

$ee = @() # Exception catcher
try{
    Get-ItemPropertyValue -Path $AgentInventoryRegKey -Name $PrimaryUserRegValue | Out-Null
}
catch{$ee += $_}

    if ($ee.Exception.Message -match "Property $PrimaryUserRegValue does not exist") {
        Write-Warning "Value doesn’t exist"
        }
    else {
        Remove-ItemProperty -Path $AgentInventoryRegKey -Name $PrimaryUserRegValue
        }


if (Test-Path "$LogLocation") {
    Remove-Item -Path $LogLocation
    }
Else {
    Write-Warning "Failed to find or verify $LogLocation"
    }


Get-Service AeXNSClient -ErrorAction SilentlyContinue | Start-Service -ErrorAction SilentlyContinue

$AltirisAgentClientClass.SendBasicInventory()