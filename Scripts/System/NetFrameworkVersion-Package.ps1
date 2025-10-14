if ($env:PROCESSOR_ARCHITEW6432 -eq "AMD64") {
    if ($myInvocation.Line) {
        &"$env:WINDIR\sysnative\windowspowershell\v1.0\powershell.exe" -NonInteractive -NoProfile $myInvocation.Line
    }
    else {
        &"$env:WINDIR\sysnative\windowspowershell\v1.0\powershell.exe" -NonInteractive -NoProfile -file "$($myInvocation.InvocationName)" $args
    }
    exit $lastexitcode
}
function Get-NetFrameworkVersion {
    <#PSScriptInfo
 
.VERSION 1.1
 
.GUID 2fac3f04-c5ac-4393-8c04-9655eba93933
 
.AUTHOR Chris Carter
 
.COMPANYNAME
 
.COPYRIGHT 2018 Chris Carter. All rights reserved.
 
.TAGS .NETFramework Version
 
.LICENSEURI http://creativecommons.org/licenses/by-sa/4.0/
 
.PROJECTURI https://gallery.technet.microsoft.com/scriptcenter/Get-NET-Framework-Version-1f5b7db3
 
.ICONURI
 
.EXTERNALMODULEDEPENDENCIES
 
.REQUIREDSCRIPTS
 
.EXTERNALSCRIPTDEPENDENCIES
 
.RELEASENOTES Initial Release; Wording changes to Help information.
 
 
#>

    <#
.SYNOPSIS
Gets the version of the .NET Framework installed.
 
.DESCRIPTION
Get-DotNet retrieves the version of the .NET Framework installed on the machine. By default it only returns the latest version installed.
 
.PARAMETER ComputerName
The name of the computer to get the .NET Framework version from.
 
.PARAMETER All
Show all versions of the .NET Framework installed.
 
.INPUTS
System.String
 
 
 
Get-DotNet accepts the property name ComputerName from the pipeline.
.OUTPUTS
PSCustomObject
 
 
 
Get-DotNet outputs a PSCustomObject representing the installed version of the .NET Framework.
.EXAMPLE
Get-DotNet
 
This command will return the latest version of the .NET Framework installed.
.EXAMPLE
Get-DotNet -ComputerName workstation-pc
 
This command will return the latest version of the .NET Framework installed on the computer workstation-pc.
.NOTES
The ComputerName parameter requires that PowerShell Remoting be enabled on the remote computer to function correctly.
.LINK
Get-ChildItem
.LINK
Get-Item
.LINK
Get-ItemProperty
.LINK
Add-member
#>
    #Requires -Version 2.0
    [CmdletBinding(HelpURI = 'https://gallery.technet.microsoft.com/scriptcenter/Get-NET-Framework-Version-1f5b7db3')]

    Param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias("Cn")]
        [String[]]$ComputerName = 'localhost',

        [Switch]$All
    )

    Begin {
        $HelperFunctions = {
            Push-Location
            Set-Location HKLM:

            Function Get-VersionInfo ($Key) {
                $install = (Get-ItemProperty $Key).Install
                $version = (Get-ItemProperty $Key).Version
                $servicePack = (Get-ItemProperty $Key).SP
                $Key.Name -match 'v(?<versionName>\d\.\d)' | Out-Null
                $versionName = $Matches.versionName

                if ($install) {
                    $output = New-Object psobject -Property @{Name = $versionName }
                    $output | Add-Member -MemberType NoteProperty -Name Version -Value $version
                }

                if ($servicePack -and $install -eq 1) {
                    $output | Add-Member -MemberType NoteProperty -Name ServicePack -Value $servicePack
                }

                $output
            }
        
            Function Get-4.5+Version ($Release) {
                switch ($Release) {
                    { $_ -le 378389 } { "4.5"; break }
                    { $_ -le 378758 } { "4.5.1"; break }
                    { $_ -le 379893 } { "4.5.2"; break }
                    { $_ -le 393297 } { "4.6"; break }
                    { $_ -le 394271 } { "4.6.1"; break }
                    { $_ -le 394806 } { "4.6.2"; break }
                    { $_ -le 460805 } { "4.7"; break }
                    { $_ -le 461310 } { "4.7.1"; break }
                    { $_ -le 461814 } { "4.7.2"; break }
                    { $_ -le 528040 } { "4.8"; break }
                    { $_ -gt 528040 } { "Newer Release than 4.8"; break }
                    default { "No 4.5+ detected" }
                }
            }

            Function Get-Version1.1-3 {
                foreach ($key in Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP') {
                    if ($key.Name -match 'v[123]') {
                        Get-VersionInfo -Key $key
                    }
                }
            }

            Function Get-Version4 {
                $keyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4'
                $keys = Get-ChildItem $keyPath

                if ($keys) {
                    if ($fullKey = Get-Item "$keyPath\Full") {
                        $info = Get-VersionInfo -Key $fullKey
                        if ( -not ($release = (Get-ItemProperty $fullKey).Release) ) {
                            $info.Name = "4.0"
                            $info
                        }
                        else {
                            $info.Name = Get-4.5+Version -Release $release
                            $info | Add-Member -MemberType NoteProperty -Name Release -Value $release
                            $info
                        }
                    }
                    else {
                        $info = Get-VersionInfo -Key (Get-Item "$keyPath\Client")
                        $info.Name = "4.0 Client"
                        $info
                    }
                }
            }
        }    
    }

    Process {
        foreach ($c in $ComputerName) {
            if ($env:COMPUTERNAME, 'localhost', '.' -contains $c) {
                . $HelperFunctions
                $result = Get-Version1.1-3
                $result += Get-Version4
            }
            else {
                $session = New-PSSession -ComputerName $c
                $result = Invoke-Command -Session $session -ScriptBlock {
                    Param($Helpers)
                    $HelperBlock = [scriptblock]::Create($Helpers)
                    . $HelperBlock
                    $result = Get-Version1.1-3
                    $result += Get-Version4
                    $result
                } -ArgumentList $HelperFunctions
                Remove-PSSession -Session $session
            }

            if ($All) { Write-Output $result }
            else { Write-Output $result[($result.Length - 1)] }
        }
    }

    End { 
        Pop-Location
    }

}

(Get-NetFrameworkVersion | ConvertTo-Csv -NoTypeInformation -Delimiter "|")[1].Replace("`"", "")