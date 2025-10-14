function Test-SoapData {
    [cmdletbinding()]
    param (
        $SoapData
    )
    [xml]$SoapDataXml = ($SoapData).Content
    if ($SoapDataXml.Envelope.Body) {
        Write-Output $true
    }
    else {
        Write-Output $false
    }
}