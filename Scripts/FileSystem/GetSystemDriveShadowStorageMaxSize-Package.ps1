if ($env:PROCESSOR_ARCHITEW6432 -eq "AMD64") {
    $x64PS = Join-Path $PSHome.tolower().replace("syswow64", "sysnative").replace("system32", "sysnative") powershell.exe
    $cmd = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($myinvocation.MyCommand.Definition))
    $out = & "$x64PS" -NonInteractive -NoProfile -ExecutionPolicy Bypass -EncodedCommand $cmd
    $out
    exit $lastexitcode
}

Try {
    $Volume = Get-CimInstance -Query "Select DeviceID, Name, Capacity from Win32_Volume WHERE DriveLetter='$Env:SystemDrive'"
    $VolumeID = $Volume.DeviceID -Replace '\{|\}|\\|\?.*olume', ''
    $ShadowStorage = Get-CimInstance Win32_ShadowStorage | Where-Object { $_.Volume.DeviceID -match $VolumeID } | Select-Object Volume, MaxSpace

    $VSSSpace = [math]::Round($ShadowStorage.MaxSpace / 1GB, 2)
    $VSSPercent = [math]::Round($ShadowStorage.MaxSpace / $Volume.Capacity * 100, 2)
    Write-Output "$($VSSPercent)|$($VSSSpace)"
}
Catch {
    Write-Error "Could not determine the Shadow Storage MaxSpace"
}