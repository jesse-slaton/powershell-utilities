<#
.SYNOPSIS
    Tests the computer's secure channel to its domain when domain controller SRV records resolve.

.DESCRIPTION
    Looks up the _ldap._tcp.dc._msdcs SRV records for the domain named by -DomainName, or
    for the domain the computer is joined to when -DomainName is not given.
    If any record resolves, runs nltest /sc_verify:<domain> and outputs True when the
    secure channel and trust verification both succeed, False when nltest runs but reports
    any error status (such as ERROR_ACCESS_DENIED from the domain controller), or False
    when nltest fails with a broken trust (ERROR_NO_LOGON_SERVERS, ERROR_NO_TRUST_LSA_SECRET,
    ERROR_NO_TRUST_SAM_ACCOUNT, ERROR_TRUSTED_DOMAIN_FAILURE or
    ERROR_TRUSTED_RELATIONSHIP_FAILURE). If nothing resolves, outputs the string
    "Unable to resolve domain controller addresses."

    Any other nltest result (for example access denied when not run as administrator,
    or an unknown domain) is a terminating error that quotes the nltest output, so a
    failure to check is never reported as True or False.

    Never repairs the channel (no /sc_reset). Changes nothing.

.PARAMETER DomainName
    DNS name of the domain to check, such as corp.contoso.com. Defaults to the domain the
    computer is joined to; without -DomainName the script stops with an error when the
    computer is not joined to a domain.

.EXAMPLE
    .\CheckDomainTrust.ps1

    Checks the secure channel to the domain this computer is joined to.

.EXAMPLE
    .\CheckDomainTrust.ps1 -DomainName corp.contoso.com

    Outputs True when the secure channel is healthy, False when it is broken, or the
    resolution message when no domain controller is found.

.NOTES
    Requires a domain-joined computer, DNS access to the domain and administrator rights
    (nltest /sc_verify needs them). Uses nltest.exe instead of Test-ComputerSecureChannel,
    which PowerShell 7 does not have, so it runs on Windows PowerShell 5.1 and PowerShell 7.
    Resolve-DnsName needs the DnsClient module (Windows 8 / Server 2012 or later).
#>
[CmdletBinding()]
param (
    [ValidatePattern('^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*$')]
    [string]$DomainName
)

function Get-TargetDomainName {
    <#
    .SYNOPSIS
        Returns -DomainName when given, else the DNS domain the computer is joined to, or throws when it is not joined.

    .PARAMETER DomainName
        Domain name given on the command line, if any.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [string]$DomainName
    )
    if ($DomainName) { return $DomainName }
    $System = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if (-not $System.PartOfDomain) {
        throw "This computer is not joined to a domain (workgroup '$($System.Domain)'). Use -DomainName to name the domain to check."
    }
    if ("$($System.Domain)" -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*$') {
        throw "The joined domain '$($System.Domain)' is not a DNS domain name. Use -DomainName to name the domain to check."
    }
    $System.Domain
}

function Invoke-NltestScVerify {
    <#
    .SYNOPSIS
        Runs nltest /sc_verify:<domain> and returns its exit code and output lines.

    .PARAMETER DomainName
        DNS name of the domain.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$DomainName
    )
    $Output = & nltest.exe "/sc_verify:$DomainName" 2>&1
    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = @($Output | ForEach-Object { "$_" })
    }
}

function ConvertFrom-NltestScVerify {
    <#
    .SYNOPSIS
        Turns nltest /sc_verify output into True (healthy), False (broken trust), or a terminating error.

    .DESCRIPTION
        Reads every "<decimal> 0x<hex> <NAME>" status in the output; nltest prints these the
        same way in every display language. When the exit code is 0, True if every status is
        0 and False if any is not (such as ERROR_ACCESS_DENIED from the domain controller).
        When nltest fails, False if a status is one of the codes that mean the trust is
        broken. Anything else throws, quoting the output.

    .PARAMETER ExitCode
        nltest's exit code.

    .PARAMETER Output
        nltest's output lines.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [int]$ExitCode,

        [AllowEmptyCollection()]
        [string[]]$Output = @()
    )
    # ERROR_NO_LOGON_SERVERS, ERROR_NO_TRUST_LSA_SECRET, ERROR_NO_TRUST_SAM_ACCOUNT,
    # ERROR_TRUSTED_DOMAIN_FAILURE, ERROR_TRUSTED_RELATIONSHIP_FAILURE.
    $BrokenTrust = 1311, 1786, 1787, 1788, 1789
    $Text = $Output -join [Environment]::NewLine
    $Statuses = @([regex]::Matches($Text, '(?<code>\d+)\s+0x[0-9A-Fa-f]+\s+[A-Za-z][A-Za-z0-9_]*') |
            ForEach-Object { [int64]$_.Groups['code'].Value })

    if ($Statuses.Count -eq 0) {
        throw "nltest /sc_verify printed no status (exit code $ExitCode): $Text"
    }
    # Exit code 0 means nltest asked the domain controller; any nonzero status is a bad channel.
    if ($ExitCode -eq 0) {
        return -not ($Statuses | Where-Object { $_ -ne 0 })
    }
    if ($Statuses | Where-Object { $BrokenTrust -contains $_ }) {
        return $false
    }
    throw "nltest /sc_verify could not check the secure channel (exit code $ExitCode): $Text"
}

function Test-DomainSecureChannel {
    <#
    .SYNOPSIS
        Outputs True or False for the secure channel to a domain, or a message when no domain controller resolves.

    .PARAMETER DomainName
        DNS name of the domain.
    #>
    [CmdletBinding()]
    [OutputType([bool], [string])]
    param (
        [Parameter(Mandatory)]
        [string]$DomainName
    )
    $Records = @(Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.$DomainName" -Type SRV -ErrorAction SilentlyContinue |
            Where-Object { $_.Type -eq 'SRV' })
    if ($Records.Count -eq 0) {
        return 'Unable to resolve domain controller addresses.'
    }
    $Result = Invoke-NltestScVerify -DomainName $DomainName
    ConvertFrom-NltestScVerify -ExitCode $Result.ExitCode -Output $Result.Output
}

Test-DomainSecureChannel -DomainName (Get-TargetDomainName -DomainName $DomainName)
