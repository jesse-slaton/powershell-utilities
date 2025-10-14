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