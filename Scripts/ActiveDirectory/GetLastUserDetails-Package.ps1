<#
.SYNOPSIS
    Attempts to report the most recent logon to this computer and how long ago it was.

.DESCRIPTION
    If started in 32-bit PowerShell on 64-bit Windows, re-runs itself in 64-bit Windows
    PowerShell through the sysnative path and exits with that run's exit code (or exits 1
    if 64-bit PowerShell is not found).

    It lists enabled local user accounts (Win32_UserAccount, LocalAccount=True,
    SIDType=1). A second query for domain accounts uses the literal filter
    "Domain='{0}'" (the placeholder is never filled in), so it normally returns
    nothing. For each account found it reads the newest event 4624 (successful logon)
    from the Security log; this is the same event for every account, not that
    account's own last logon.

    It then tries to write "<Account>|<Elapsed>", where Elapsed is "Less than 1 day",
    "1 day" or "<n> days". Because the Username field holds the account object (Name and
    Domain) rather than a string, this concatenation is likely to fail with an error
    instead of producing the line. When no account or no logon event is found it writes
    "No users have logged on to this machine." Read-only.

.EXAMPLE
    .\GetLastUserDetails-Package.ps1

    Runs the check on the local computer.

.NOTES
    Requires administrator rights (reading the Security event log) and Windows
    PowerShell 5.1 (it relaunches powershell.exe for the 64-bit re-run). Named and
    written as a deployment package that runs under Local System.
#>
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
