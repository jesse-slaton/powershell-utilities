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