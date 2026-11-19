<#
.SYNOPSIS
    Tests whether web traffic is going through the Symantec (Broadcom) WSS/ThreatPulse proxy.

.DESCRIPTION
    Requests http://test.threatpulse.com and outputs True when the response contains the
    ThreatPulse "currently protecting your browser" text, otherwise False. If the request
    fails, it first outputs the HTTP status code of the failure (when there is one).

.EXAMPLE
    .\Test-Threatpulse.ps1

    True

.NOTES
    Needs outbound HTTP access to test.threatpulse.com. No admin rights needed.
#>
Try {
    $ThreatpulseResponse = Invoke-RestMethod -Uri 'http://test.threatpulse.com'
}
Catch {
    Write-Output $_.Exception.Response.Statuscode.value__
}
$ThreatpulseResponse -match 'Threatpulse is currently protecting your browser from'