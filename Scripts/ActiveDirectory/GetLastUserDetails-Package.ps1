if ($env:PROCESSOR_ARCHITECTURE -eq "x86")
{
    $sysnativePath = "$env:windir\sysnative\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path $sysnativePath)
    {
        & $sysnativePath -File $MyInvocation.MyCommand.Path
        exit $LASTEXITCODE
    }
    else
    {
        Write-Error "Unable to locate 64-bit PowerShell."
        exit 1
    }
}

function Convert-TimeSpanToHumanReadable {
    param(
        [TimeSpan]$TimeSpan
    )
    $Days = $TimeSpan.Days

    if ($Days -gt 1) {
        return "$Days days"
    } elseif ($Days -eq 1) {
        return "1 day"
    } elseif ($Days -lt 1) {
        return "Less than 1 day"
    }
}

$users = @()

# Get local user accounts
$localUsers = Get-CIMInstance -Class Win32_UserAccount -Filter "LocalAccount=True AND Disabled=False AND SIDType=1" -ErrorAction SilentlyContinue
$users += $localUsers | Select-Object -Property Name, Domain

# Get domain user accounts
$domainUsers = Get-CIMInstance -Class Win32_UserAccount -Filter "Domain='{0}' AND Disabled=False AND SIDType=1" -ErrorAction SilentlyContinue
$users += $domainUsers | Select-Object -Propert Name, Domain

$results = foreach ($user in $users) {
    $logonEvents = Get-WinEvent -FilterHashtable @{logname='security';id=4624} -MaxEvents 1
    if ($null -ne $logonEvents) {
        $lastLogon = $logonEvents[0].TimeCreated
        [pscustomobject]@{
            Username = $user
            LastLogon = $lastLogon
        }
    }
}

$mostRecent = $results | sort-object LastLogon -Descending | select-object -First 1

if ($null -ne $mostRecent) {
    $elapsedTime = Convert-TimeSpanToHumanReadable (New-TimeSpan -Start $mostRecent.LastLogon -End (Get-Date))
    $mostRecent.Username + "|" + $elapsedTime
} else {
    "No users have logged on to this machine."
}
