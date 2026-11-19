<#
.SYNOPSIS
    Defines Test-SoapData, which checks that a web response contains a SOAP envelope body.

.DESCRIPTION
    Running the script only defines the Test-SoapData function; it writes no output.
    Dot-source the script, then call the function.

    Test-SoapData -SoapData <response> casts the Content property of the object it is
    given (for example the result of Invoke-WebRequest) to [xml] and outputs $true when
    Envelope.Body has a value, otherwise $false. Content that is not valid XML makes the
    cast fail with an error. Read-only; it sends no request itself.

.EXAMPLE
    . .\Test-SoapData.ps1
    $response = Invoke-WebRequest -Uri $Uri -Method Post -Body $Envelope -ContentType 'text/xml' -UseBasicParsing
    Test-SoapData -SoapData $response

    Outputs True when the response holds a SOAP body.

.EXAMPLE
    . .\Test-SoapData.ps1
    Test-SoapData -SoapData ([pscustomobject]@{ Content = '<Envelope><Body><Ok/></Body></Envelope>' })

    True

.NOTES
    None. Making the SOAP request that produces the response needs network access to
    the service.
#>


function Test-SoapData {
    <#
    .SYNOPSIS
        Checks that a web response contains a SOAP envelope body.

    .DESCRIPTION
        Casts the Content property of SoapData to [xml] and outputs $true when
        Envelope.Body has a value, otherwise $false. Content that is not valid XML makes
        the cast fail with an error.

    .PARAMETER SoapData
        Object with a Content property holding the response text, for example the result
        of Invoke-WebRequest.

    .EXAMPLE
        Test-SoapData -SoapData $response

        Outputs True when $response.Content holds a SOAP body.

    .EXAMPLE
        Test-SoapData -SoapData ([pscustomobject]@{ Content = '<Envelope><Body><Ok/></Body></Envelope>' })

        True

    .NOTES
        None.
    #>
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