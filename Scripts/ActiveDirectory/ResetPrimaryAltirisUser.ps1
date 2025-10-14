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