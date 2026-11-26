<#
.SYNOPSIS
    Reports how long ago Group Policy last finished processing for the computer.

.DESCRIPTION
    Reads the endTimeHi and endTimeLo values of the core Group Policy extension state
    key (HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\
    Extension-List\{00000000-0000-0000-0000-000000000000}), combines them into a
    file time, and writes the time elapsed since then as text:

    - "Less than 1 hour", "1 hour" or "<n> hours" when it was under a day ago
    - "1 day" or "<n> days" when it was 1 to 364 days ago
    - "Over 1 year" when it was 365 days or more ago
    - "Could not get last GPUpdate datetime" if the registry values are missing or
      cannot be read or converted

    Runs in-process in the current PowerShell; it needs no PowerShell remoting. Read-only.

    The key is read through the 64-bit registry view
    ([Microsoft.Win32.RegistryView]::Registry64), so a 32-bit host on 64-bit Windows
    reads the same values as a 64-bit host whether or not WOW64 redirects this key.

.EXAMPLE
    .\GetLastComputerPolicyRefresh.ps1

    3 hours

.NOTES
    Windows PowerShell 5.1 or PowerShell 7 on Windows. Reading the key needs no
    administrator rights.
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
        Key path under HKEY_LOCAL_MACHINE.

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

function Get-LastComputerPolicyRefresh {
    <#
    .SYNOPSIS
        Returns the time since the last computer Group Policy refresh as text.

    .PARAMETER Now
        The time to measure from. Defaults to the current time.
    #>
    param(
        [datetime]$Now = (Get-Date)
    )

    $SubKey = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Extension-List\{00000000-0000-0000-0000-000000000000}'
    $Failure = 'Could not get last GPUpdate datetime'
    try {
        $EndTimeHi = Get-LocalMachineRegistryValue -SubKey $SubKey -Name 'endTimeHi'
        $EndTimeLo = Get-LocalMachineRegistryValue -SubKey $SubKey -Name 'endTimeLo'
        if ($null -eq $EndTimeHi -or $null -eq $EndTimeLo) { return $Failure }
        # REG_DWORD values come back as signed Int32; mask the low half so a value with its
        # top bit set does not sign-extend over the high half.
        $FileTime = ([Int64]$EndTimeHi -shl 32) -bor ([Int64]$EndTimeLo -band [Int64]4294967295)
        $Diff = New-TimeSpan -Start ([datetime]::FromFileTime($FileTime)) -End $Now
    }
    catch {
        return $Failure
    }

    if ($Diff.Days -ge 365) { return 'Over 1 year' }
    if ($Diff.Days -eq 1) { return '1 day' }
    if ($Diff.Days -gt 1) { return "$($Diff.Days) days" }
    switch ($Diff.Hours) {
        { $_ -lt 1 } { return 'Less than 1 hour' }
        1 { return '1 hour' }
        default { return "$($Diff.Hours) hours" }
    }
}

Write-Output (Get-LastComputerPolicyRefresh)
