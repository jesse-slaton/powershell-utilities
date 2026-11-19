<#
.SYNOPSIS
    Defines Get-WindowsErrorCodeInfo, which looks up Windows error codes in a downloaded JSON list.

.DESCRIPTION
    Defines the Get-WindowsErrorCodeInfo function and does nothing else: running the
    script without dot-sourcing it produces no output and leaves nothing defined. The
    function downloads a JSON list of Windows error codes from a GitHub gist (or reads
    .\ErrorCodes.json) and outputs the entries that match an exit code, or all entries.
    See Get-Help Get-WindowsErrorCodeInfo -Full for its parameters. Read-only.

.EXAMPLE
    . .\Get-WindowsErrorCodeInfo.ps1
    Get-WindowsErrorCodeInfo -ExitCode 5

    Dot-sources the script, then looks up exit code 5 in the downloaded list.

.EXAMPLE
    . .\Get-WindowsErrorCodeInfo.ps1
    1603, 1618 | Get-WindowsErrorCodeInfo

    Looks up two exit codes from the pipeline.

.NOTES
    Needs network access to gist.githubusercontent.com unless -LocalJSONFilePath is
    used. Works in Windows PowerShell 5.1 and PowerShell 7. No admin rights needed.
#>


Function Get-WindowsErrorCodeInfo
{
<#
.SYNOPSIS
    Looks up Windows error (exit) codes in a JSON list downloaded from a GitHub gist.

.DESCRIPTION
    In its begin block, loads the error-code list: from .\ErrorCodes.json in the current
    folder when LocalJSONFilePath is set, otherwise by downloading GithubJSONUrl with
    Invoke-WebRequest and converting it from JSON. With ExitCode, outputs the entries
    whose exitCode property equals ExitCode. Without it, outputs every entry. If loading
    the list throws, outputs the string "Something went wrong! please try running the
    script again." Read-only.

.PARAMETER ExitCode
    Exit code to look up, for example 5. Accepts pipeline input. When omitted or
    empty, every entry is returned.

.PARAMETER LocalJSONFilePath
    When set to any non-empty value, the list is read from .\ErrorCodes.json in the
    current folder instead of being downloaded. The value itself is not used as the
    path.

.PARAMETER GithubJSONUrl
    URL of the JSON list to download. Defaults to a public gist
    (WindowsErrorCode.JSON on gist.githubusercontent.com).

.EXAMPLE
    Get-WindowsErrorCodeInfo -ExitCode 5

    Downloads the list and returns any entries whose exitCode is 5.

.EXAMPLE
    Get-WindowsErrorCodeInfo -ExitCode 1603 -LocalJSONFilePath yes

    Reads .\ErrorCodes.json from the current folder and returns any entries whose
    exitCode is 1603.
#>
[cmdletbinding()]
Param(
        [Parameter(ValueFromPipeline = $true)][String]$ExitCode,
        [String]$LocalJSONFilePath,
        [String]$GithubJSONUrl = "https://gist.githubusercontent.com/PrateekKumarSingh/72e5deda930831f0bb41a3518d2464e1/raw/ce98cc4120066b53ae738abf7d38668980cbaafd/WindowsErrorCode.JSON"
)

Begin
{
    Try
    {

        If($LocalJSONFilePath)
        {
            $JSON = Get-Content .\ErrorCodes.json -Raw |ConvertFrom-Json
        }
        ElseIf($GithubJSONUrl)
        {
            $JSON = (Invoke-WebRequest -Uri $GithubJSONUrl).content | ConvertFrom-Json
        }
    }
    Catch
    {
        "Something went wrong! please try running the script again."
    }
}

Process
{
    Foreach($Item in $ExitCode)
    {
        If($Item)
	    {
			$JSON.PSObject.BaseObject | Where{$_.exitCode -eq $ExitCode}
	    }
        else
        {
            $JSON.PSObject.BaseObject 
            break;
        }
    }

}

End
{}

}