<#
.SYNOPSIS
    Outputs the hash of a file, with the path and algorithm supplied as Tanium parameters.

.DESCRIPTION
    If started in 32-bit PowerShell on 64-bit Windows, passes
    $MyInvocation.MyCommand.Definition to the 64-bit powershell.exe (sysnative) with
    -EncodedCommand, writes its output, and exits with its exit code.

    Otherwise it URL-decodes the FilePath value with System.Web.HttpUtility, and if that
    path exists, outputs (Get-FileHash -Algorithm <HashType>).Hash, the hash as an
    uppercase hex string. If the path does not exist, writes the error "Could not get
    the file hash". Read-only.

    The script has no param() block. FilePath and HashType are Tanium package
    parameters: Tanium replaces the '||FilePath||' and '||HashType||' tokens before the
    script runs. HashType must be an algorithm Get-FileHash accepts, such as SHA256 or
    MD5.

.EXAMPLE
    .\TaniumFileHash-Package.ps1

    Run by Tanium as a package with FilePath and HashType set; outputs <HashValue>.

.NOTES
    Requires the Tanium Client to substitute the ||FilePath|| and ||HashType||
    parameters; run outside Tanium, the literal tokens are used and the path is not
    found. Written for Windows PowerShell (it loads System.Web and re-runs in
    powershell.exe). Reading the file needs whatever rights the file requires.
#>
if ($env:PROCESSOR_ARCHITEW6432 -eq "AMD64") {
    $x64PS = Join-Path $PSHome.ToLower().Replace("syswow64", "sysnative").Replace("system32", "sysnative") Powershell.exe
    $cmd = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($myinvocation.MyCommand.Definition))
    $Out = & "$x64PS" -NonInteractive -NoProfile -ExecutionPolicy Bypass -EncodedCommand $cmd
    $Out
    exit $LASTEXITCODE
}
 
# Start your script below
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.web")
$EncodedPath = [System.Web.HttpUtility]::URLDecode("||FilePath||")
$HashType = '||HashType||'

If (Test-Path -Path "$EncodedPath") {
    (Get-FileHash -Path "$EncodedPath" -Algorithm $HashType).Hash
}
Else {
    Write-Error "Could not get the file hash"
}