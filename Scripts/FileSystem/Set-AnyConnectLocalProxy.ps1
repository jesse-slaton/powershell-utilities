<#
.SYNOPSIS
    Sets AllowLocalProxyConnections to true in the Cisco AnyConnect profile XML files.

.DESCRIPTION
    Looks in $env:ProgramData\Cisco\Cisco AnyConnect Secure Mobility Client\Profile. For
    each .xml file there that contains
    <AllowLocalProxyConnections>false</AllowLocalProxyConnections>, replaces it with
    <AllowLocalProxyConnections>true</AllowLocalProxyConnections> and rewrites the file
    with Set-Content -Force. Outputs one object per .xml file with computerName,
    fileName, and result ('Applied changes' or 'No changes required'). If the Profile
    folder does not exist, does nothing and outputs nothing. A terminating error
    that stops the loop is caught and written with Write-Error.

.EXAMPLE
    .\Set-AnyConnectLocalProxy.ps1

    Updates the AnyConnect profiles and lists the result for each profile file.

.NOTES
    Requires administrator rights (writes under ProgramData) and the Cisco AnyConnect
    Secure Mobility Client profile folder. Set-Content writes the file in the default
    encoding of the PowerShell edition that runs it, which can differ from the original
    file's encoding. The change takes effect when AnyConnect reloads the profile.
    getVPNProfileReady-Sensor.ps1 is the related check.
#>
$path = "$env:programdata\Cisco\Cisco AnyConnect Secure Mobility Client\Profile"
if (Test-Path $path) {
    try {
        $targetFile = Get-ChildItem -Path $path -Filter *.xml
        $report = @()
        foreach ( $f in $targetFile ) {
            $content = Get-Content -Path $f.FullName -Raw
            if ($content -match '<AllowLocalProxyConnections>false</AllowLocalProxyConnections>') {
                $content.Replace('<AllowLocalProxyConnections>false</AllowLocalProxyConnections>', '<AllowLocalProxyConnections>true</AllowLocalProxyConnections>') | Set-Content -Path $f.FullName -Force
                #Write-Output "$($f.Name): Applied changes"
                $result = 'Applied changes'
            }
            else {
                #Write-Output "$($f.Name): No changes required"
                $result = 'No changes required'
            }
            $obj = [PSCustomObject]@{
                computerName = $env:COMPUTERNAME
                fileName     = $f.Name
                result       = $result
            }
            $report += $obj
        }
        $report
    }
    catch {
        Write-Error $_.exception
    }
}