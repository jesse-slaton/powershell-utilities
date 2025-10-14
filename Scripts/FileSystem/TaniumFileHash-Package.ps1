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