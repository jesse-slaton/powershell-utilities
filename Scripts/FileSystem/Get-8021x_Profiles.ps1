#Requires -Version 2

<#
.SYNOPSIS
    Outputs the 802.1X settings of the first wired LAN profile as one pipe-delimited line.

.DESCRIPTION
    Runs 'netsh lan show profiles' and parses its text output into one object per
    profile (the object is emitted when the "Cache user information" line is read). It
    then writes the first profile as:

        <ProfileOnInterface>|<Type>|<Enabled802_1x>|<Enforced802_1x>|<EAPType>|<AuthCredential802_1x>

    Read-only. The script also defines an Enable-Service helper that starts the Wired
    AutoConfig service (dot3svc), but the call to it is commented out, so the service is
    not started. If netsh returns no profile (for example because dot3svc is stopped),
    indexing the empty result fails with an error.

.EXAMPLE
    .\Get-8021x_Profiles.ps1

    <InterfaceName>|<Type>|Enabled|<Enforcement>|<EAPType>|<AuthCredential>

.NOTES
    Requires the Wired AutoConfig service (dot3svc) to be running. The parser reads
    English netsh output. The #Requires -Version 2 line understates the requirement:
    the code uses [ordered] and [Parameter(Mandatory)], which need PowerShell 3.0 or
    later. No admin rights needed.
#>


#PowerShell

function ConvertFrom-NetshProfiles {
[CmdletBinding()]
Param(
    [Parameter(Mandatory,Position=0)]
    [array]$Profiles
)
    $Hash = [ordered]@{}
    foreach($line in $Profiles){
        if ($line -notmatch "======================================================================="){
            switch -Regex ($line){
                '^Profile on interface\s+(?<ProfileOnInterface>.*$)'{$Hash.ProfileOnInterface = $Matches.ProfileOnInterface;Break}
                '^Applied:\s+(?<Applied>.*$)'{$Hash.Applied = $Matches.Applied;Break}
                '\s*Profile version\s*:\s+(?<ProfileVersion>.*$)'{$Hash.ProfileVersion = $Matches.ProfileVersion;Break}
                '\s{4,}Type\s*:\s+(?<Type>.*$)'{$Hash.Type = $Matches.Type;Break}
                '\s*AutoConfig Version\s*:\s+(?<AutoConfigVersion>.*$)'{$Hash.AutoConfigVersion = $Matches.AutoConfigVersion;Break}
                '\s*802\.1x\s*:\s+(?<Enforced802_1x>(?!Enabled).*$)'{$Hash.Enforced802_1x = $Matches.Enforced802_1x;Break}
                '\s*802\.1x\s*:\s+(?<Enabled802_1x>.*$)'{$Hash.Enabled802_1x = $Matches.Enabled802_1x;Break}
                '\s*EAP type\s*:\s+(?<EAPType>.*$)'{$Hash.EAPType = $Matches.EAPType;Break}
                '\s*802\.1X auth credential\s*:\s+(?<AuthCredential802_1x>.*$)'{$Hash.AuthCredential802_1x = $Matches.AuthCredential802_1x;Break}
                '\s*Cache user information\s*:\s+(?<CacheUserInformation>.*$)'{$Hash.CacheUserInformation = $Matches.CacheUserInformation;Write-Output (New-Object psobject -Property $Hash);Break}
                default {Break}
            }
        }
    }
}

function Enable-Service {
[CmdletBinding()]
Param(
    [Parameter(Position=0)]
    [string] $ServiceName = 'dot3svc'
)

    if((Get-Service $ServiceName).Status -ne 'Running'){
        try{
            Start-Service $ServiceName -ErrorAction Stop
        }
        catch{
            throw "Check that $ServiceName is running."
        }
    }
}

#Enable-Service
$dot1x = ConvertFrom-NetshProfiles -Profiles (& netsh lan show profiles)

$dot1x[0].ProfileOnInterface + "|" + $dot1x[0].Type + "|" + $dot1x[0].Enabled802_1x + "|" + $dot1x[0].Enforced802_1x + "|" + $dot1x[0].EAPType + "|" + $dot1x[0].AuthCredential802_1x