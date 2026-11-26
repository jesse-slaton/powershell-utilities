function Test-Wow64Process {
    <#
    .SYNOPSIS
        Returns $true when PowerShell runs as a 32-bit process on 64-bit Windows.

    .DESCRIPTION
        Compares the operating system and process bitness. A 32-bit process on 64-bit Windows
        runs under WOW64. Private to StorageHealth.

    .EXAMPLE
        Test-Wow64Process

        Returns $true in C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe on 64-bit
        Windows, and $false in 64-bit PowerShell.

    .NOTES
        Runs on Windows PowerShell 5.1 and PowerShell 7.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    [Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess
}

function Invoke-Wow64CimQuery {
    <#
    .SYNOPSIS
        Queries a root/cimv2 class through its 64-bit WMI provider from a 32-bit process.

    .DESCRIPTION
        Runs SELECT * FROM <ClassName> with the __ProviderArchitecture=64 and
        __RequiredArchitecture WMI context options, so WMI loads the 64-bit provider even
        though the caller is 32-bit. The Volume Shadow Copy provider needs this: queried from
        a WOW64 process without it, Win32_ShadowCopy and Win32_ShadowStorage fail with
        "Initialization failure". Private to StorageHealth.

    .PARAMETER ClassName
        The root/cimv2 class to query.

    .EXAMPLE
        Invoke-Wow64CimQuery -ClassName Win32_ShadowCopy

        Returns every shadow copy, from 32-bit PowerShell on 64-bit Windows.

    .NOTES
        Windows only. Runs on Windows PowerShell 5.1 and PowerShell 7.
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Management.Infrastructure.CimInstance])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClassName
    )

    $options = New-Object -TypeName Microsoft.Management.Infrastructure.Options.CimOperationOptions
    $options.SetCustomOption('__ProviderArchitecture', 64, $false)
    $options.SetCustomOption('__RequiredArchitecture', $true, $false)
    $session = New-CimSession -ErrorAction Stop
    try {
        # Enumerate before the session is closed.
        @($session.QueryInstances('root/cimv2', 'WQL', "SELECT * FROM $ClassName", $options))
    }
    finally {
        Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue
    }
}

function Get-ShadowCimInstance {
    <#
    .SYNOPSIS
        Returns the instances of a Volume Shadow Copy CIM class, from either process bitness.

    .DESCRIPTION
        Queries Win32_ShadowCopy or Win32_ShadowStorage with Get-CimInstance. From 32-bit
        PowerShell on 64-bit Windows, where the shadow copy provider fails with
        "Initialization failure", it queries through the 64-bit provider instead
        (Invoke-Wow64CimQuery). A query error is a terminating error. Private to StorageHealth.

    .PARAMETER ClassName
        Win32_ShadowCopy or Win32_ShadowStorage.

    .EXAMPLE
        Get-ShadowCimInstance -ClassName Win32_ShadowCopy

        Returns every shadow copy on the computer.

    .NOTES
        Windows only. Reading these classes normally requires administrator rights. Runs on
        Windows PowerShell 5.1 and PowerShell 7.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Win32_ShadowCopy', 'Win32_ShadowStorage')]
        [string]$ClassName
    )

    if (Test-Wow64Process) {
        Invoke-Wow64CimQuery -ClassName $ClassName -ErrorAction Stop
    }
    else {
        Get-CimInstance -ClassName $ClassName -ErrorAction Stop
    }
}
