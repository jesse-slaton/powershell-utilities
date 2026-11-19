<#
.SYNOPSIS
    Outputs the 802.1X settings of the first wired LAN profile and the dot3svc status.

.DESCRIPTION
    Checks the Wired AutoConfig service (dot3svc). If it is not running, the script sets
    it to start automatically and starts it (Set-Service -StartupType Automatic -Status
    Running), and throws "Check that dot3svc is running." if that fails.

    It then runs 'netsh lan show profiles', parses the text output into one object per
    profile, and writes the first profile as one line:

        <ProfileOnInterface>|<Type>|<Enabled802_1x>|<Enforced802_1x>|<EAPType>|<AuthCredential802_1x>|<ServiceStatus>

    ServiceStatus is the dot3svc status read before any start attempt. If netsh returns
    no profile, indexing the empty result fails with an error.

.EXAMPLE
    .\Get-WiredLANProfile.ps1

    <InterfaceName>|<Type>|Enabled|<Enforcement>|<EAPType>|<AuthCredential>|Running

.NOTES
    Requires administrator rights when dot3svc is not running (it changes the service
    startup type and starts it). The parser reads English netsh output. PowerShell 3.0
    or later.
#>


function ConvertFrom-NetshProfiles {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory, Position = 0)]
        [array]$Profiles
    )
    $Hash = [ordered]@{}
    foreach ($line in $Profiles) {
        if ($line -notmatch "=======================================================================") {
            switch -Regex ($line) {
                '^Profile on interface\s+(?<ProfileOnInterface>.*$)' {$Hash.ProfileOnInterface = $Matches.ProfileOnInterface; Break}
                '^Applied:\s+(?<Applied>.*$)' {$Hash.Applied = $Matches.Applied; Break}
                '\s*Profile version\s*:\s+(?<ProfileVersion>.*$)' {$Hash.ProfileVersion = $Matches.ProfileVersion; Break}
                '\s{4,}Type\s*:\s+(?<Type>.*$)' {$Hash.Type = $Matches.Type; Break}
                '\s*AutoConfig Version\s*:\s+(?<AutoConfigVersion>.*$)' {$Hash.AutoConfigVersion = $Matches.AutoConfigVersion; Break}
                '\s*802\.1x\s*:\s+(?<Enforced802_1x>(?!Enabled).*$)' {$Hash.Enforced802_1x = $Matches.Enforced802_1x; Break}
                '\s*802\.1x\s*:\s+(?<Enabled802_1x>.*$)' {$Hash.Enabled802_1x = $Matches.Enabled802_1x; Break}
                '\s*EAP type\s*:\s+(?<EAPType>.*$)' {$Hash.EAPType = $Matches.EAPType; Break}
                '\s*802\.1X auth credential\s*:\s+(?<AuthCredential802_1x>.*$)' {$Hash.AuthCredential802_1x = $Matches.AuthCredential802_1x; Break}
                '\s*Cache user information\s*:\s+(?<CacheUserInformation>.*$)' {$Hash.CacheUserInformation = $Matches.CacheUserInformation; Write-Output (New-Object psobject -Property $Hash); Break}
                default {Break}
            }
        }
    }
}

$ServiceName = 'dot3svc'
$ServiceStatus = (Get-Service $ServiceName).Status
if ($ServiceStatus -ne 'Running') {
    try {
        Set-Service -Name $ServiceName -StartupType Automatic -Status Running -ErrorAction Stop
    }
    catch {
        throw "Check that $ServiceName is running."
    }$
}

$dot1x = ConvertFrom-NetshProfiles -Profiles (& netsh lan show profiles)

$dot1x[0].ProfileOnInterface + "|" + $dot1x[0].Type + "|" + $dot1x[0].Enabled802_1x + "|" + $dot1x[0].Enforced802_1x + "|" + $dot1x[0].EAPType + "|" + $dot1x[0].AuthCredential802_1x + "|" + $ServiceStatus