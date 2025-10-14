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
