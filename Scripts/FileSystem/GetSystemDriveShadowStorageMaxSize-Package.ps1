<#
.SYNOPSIS
    Outputs the shadow storage maximum size of the system drive as a percentage and in GB.

.DESCRIPTION
    If started in 32-bit PowerShell on 64-bit Windows, passes
    $MyInvocation.MyCommand.Definition to the 64-bit powershell.exe (sysnative) with
    -EncodedCommand, writes its output, and exits with its exit code.

    Otherwise it reads the Win32_Volume for $env:SystemDrive and the matching
    Win32_ShadowStorage entry, and writes one line:

        <MaxSpacePercentOfVolume>|<MaxSpaceGB>

    Both values are rounded to two decimals. If a query fails, writes the error "Could
    not determine the Shadow Storage MaxSpace". Read-only.

.EXAMPLE
    .\GetSystemDriveShadowStorageMaxSize-Package.ps1

    <MaxSpacePercent>|<MaxSpaceGB>

.NOTES
    Written as a deployment package. Reading Win32_ShadowStorage normally requires
    administrator rights. The 64-bit re-run uses powershell.exe (Windows PowerShell).
#>
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