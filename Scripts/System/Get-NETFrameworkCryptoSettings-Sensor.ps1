<#
.SYNOPSIS
    Reports the .NET Framework SystemDefaultTlsVersions and SchUseStrongCrypto registry settings.

.DESCRIPTION
    Reads SystemDefaultTlsVersions and SchUseStrongCrypto from these keys, in order:

        HKLM:\SOFTWARE\Microsoft\.NETFramework\v2.0.50727
        HKLM:\SOFTWARE\Wow6432node\Microsoft\.NETFramework\v2.0.50727
        HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319
        HKLM:\SOFTWARE\Wow6432node\Microsoft\.NETFramework\v4.0.30319

    For each key it emits True when the value equals 1 and False otherwise (including
    when the value or key is missing; Get-ItemProperty then also writes a non-terminating
    error). Outputs one line of eight pipe-delimited values: for each key in the order
    above, SystemDefaultTlsVersions|SchUseStrongCrypto. Read-only.

    When started from 32-bit PowerShell on 64-bit Windows, the script first tries to
    relaunch itself in 64-bit PowerShell through the sysnative path and exits with that
    process's exit code.

.EXAMPLE
    .\Get-NETFrameworkCryptoSettings-Sensor.ps1

    True|True|False|False|True|True|True|True

    Example shape only; the values depend on the computer's registry.

.NOTES
    Windows PowerShell 5.1 (the 64-bit relaunch targets powershell.exe). No admin rights
    needed to read these keys. Shaped as an endpoint-management sensor (single delimited
    line).
#>
#Switch to 64-bit Powershell
if ($env:PROCESSOR_ARCHITEW6432 -eq "AMD64") {
    if ($myInvocation.Line) {
        &"$env:WINDIR\sysnative\powershell\v1.0\powershell.exe" -NonInteractive -NoProfile $myInvocation.Line
    }
    else {
        &"$env:WINDIR\sysnative\powershell\v1.0\powershell.exe" -NonInteractive -NoProfile -file "$($myInvocation.InvocationName)" $args
    }
    exit $lastexitcode
}
$Paths = @(
    "HKLM:\SOFTWARE\Microsoft\.NETFramework\v2.0.50727", `
        "HKLM:\SOFTWARE\Wow6432node\Microsoft\.NETFramework\v2.0.50727", `
        "HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319", `
        "HKLM:\SOFTWARE\Wow6432node\Microsoft\.NETFramework\v4.0.30319"
)
$Results = $Null
ForEach ($Path in $Paths) {
    $SystemDefaultTlsVersionsValue = $False
    $SchUseStrongCryptoValue = $False
    $SystemDefaultTlsVersions = Get-ItemProperty -Path "$Path" -Name "SystemDefaultTlsVersions"
    $SchUseStrongCrypto = Get-ItemProperty -Path "$Path" -Name "SchUseStrongCrypto"
    If ($SystemDefaultTlsVersions.SystemDefaultTlsVersions -eq 1) { $SystemDefaultTlsVersionsValue = $True }
    If ($SchUseStrongCrypto.SchUseStrongCrypto -eq 1) { $SchUseStrongCryptoValue = $True }
    $Results = $Results + $SystemDefaultTlsVersionsValue.ToString() + '|' + $SchUseStrongCryptoValue.ToString() + '|'
}

Write-Output $Results.Substring(0, $Results.Length - 1)
