Try {
    $ThreatpulseResponse = Invoke-RestMethod -Uri 'http://test.threatpulse.com'
}
Catch {
    Write-Output $_.Exception.Response.Statuscode.value__
}
$ThreatpulseResponse -match 'Threatpulse is currently protecting your browser from'