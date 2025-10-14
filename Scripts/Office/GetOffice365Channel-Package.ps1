if ($env:PROCESSOR_ARCHITEW6432 -eq "AMD64") {
    $x64PS = Join-Path $PSHome.tolower().replace("syswow64", "sysnative").replace("system32", "sysnative") powershell.exe
    $cmd = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($myinvocation.MyCommand.Definition))
    $out = & "$x64PS" -NonInteractive -NoProfile -ExecutionPolicy Bypass -EncodedCommand $cmd
    $out
    exit $lastexitcode
}

$RegChannelURL = (Get-ItemProperty -Path Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Office\ClickToRun\Configuration).CDNBaseUrl 

$ChannelHash = [ordered]@{
    "http://officecdn.microsoft.com/pr/492350f6-3a01-4f97-b9c0-c7c6ddf67d60" = "Current Channel";
    "http://officecdn.microsoft.com/pr/7ffbc6bf-bc32-4f92-8982-f9dd17fd3114" = "Semi-Annual Enterprise Channel";
    "http://officecdn.microsoft.com/pr/b8f9b850-328d-4355-9145-c59439a0c4cf" = "Semi-Annual Enterprise Channel (Preview)";
    "http://officecdn.microsoft.com/pr/5440fd1f-7ecb-4221-8110-145efaa6372f" = "Beta Channel";
    "http://officecdn.microsoft.com/pr/64256afe-f5d9-4f86-8936-8840a6a4f5be" = "Current Channel (Preview)";
    "http://officecdn.microsoft.com/pr/ea4a4090-de26-49d7-93c1-91bff9e53fc3" = "DevMain Channel";
    "http://officecdn.microsoft.com/pr/55336b82-a18d-4dd6-b5f6-9e5095c314a6" = "Monthly Enterprise Channel"
}

Write-Output $ChannelHash.$RegChannelURL
