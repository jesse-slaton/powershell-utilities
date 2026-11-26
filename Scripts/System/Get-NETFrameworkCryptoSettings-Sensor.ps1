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
    when the value or key is missing). Outputs one line of eight pipe-delimited values:
    for each key in the order above, SystemDefaultTlsVersions|SchUseStrongCrypto.
    Read-only.

    Reads the 64-bit registry view directly ([Microsoft.Win32.RegistryView]::Registry64),
    so a 32-bit host on 64-bit Windows reports the same values as a 64-bit host without
    relaunching itself in another PowerShell. Runs in-process on Windows PowerShell 5.1 and
    PowerShell 7.

.EXAMPLE
    .\Get-NETFrameworkCryptoSettings-Sensor.ps1

    True|True|False|False|True|True|True|True

    Example shape only; the values depend on the computer's registry.

.NOTES
    Windows PowerShell 5.1 or PowerShell 7 on Windows. No admin rights needed to read
    these keys. Shaped as an endpoint-management sensor (single delimited line).
#>
function Get-LocalMachineRegistryValue {
    <#
    .SYNOPSIS
        Returns one HKLM value from the 64-bit registry view, or $null when the key or value is missing.

    .DESCRIPTION
        Opens HKEY_LOCAL_MACHINE with RegistryView.Registry64, so a 32-bit PowerShell host
        on 64-bit Windows is not redirected to Wow6432Node. On 32-bit Windows the view
        falls back to the only registry there is.

    .PARAMETER SubKey
        Key path under HKEY_LOCAL_MACHINE, such as SOFTWARE\Microsoft\.NETFramework\v4.0.30319.

    .PARAMETER Name
        Value name to read.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SubKey,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $BaseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
    try {
        $Key = $BaseKey.OpenSubKey($SubKey)
        if ($null -eq $Key) { return $null }
        try { $Key.GetValue($Name) }
        finally { $Key.Dispose() }
    }
    finally {
        $BaseKey.Dispose()
    }
}

function Get-NetFrameworkCryptoSetting {
    <#
    .SYNOPSIS
        Builds the sensor line: SystemDefaultTlsVersions|SchUseStrongCrypto for each .NET Framework key.

    .DESCRIPTION
        Reads both values under each key from the 64-bit registry view and writes one
        string of eight pipe-delimited True/False values, in the key order listed in the
        script help. A value is True only when it equals 1.
    #>
    $SubKeys = @(
        'SOFTWARE\Microsoft\.NETFramework\v2.0.50727'
        'SOFTWARE\Wow6432node\Microsoft\.NETFramework\v2.0.50727'
        'SOFTWARE\Microsoft\.NETFramework\v4.0.30319'
        'SOFTWARE\Wow6432node\Microsoft\.NETFramework\v4.0.30319'
    )
    $Results = foreach ($SubKey in $SubKeys) {
        foreach ($Name in 'SystemDefaultTlsVersions', 'SchUseStrongCrypto') {
            ((Get-LocalMachineRegistryValue -SubKey $SubKey -Name $Name) -eq 1).ToString()
        }
    }
    $Results -join '|'
}

Write-Output (Get-NetFrameworkCryptoSetting)
