# Thin wrappers around environment-variable reads and writes, the change broadcast and
# directory checks, plus the one PATH splitter. Every such call in PathRepair goes through
# these functions so tests can mock them on any OS (the User environment scope and
# WM_SETTINGCHANGE exist only on Windows). Each one is self-contained, calling nothing else
# in the module, so its definition can be sent to a remote session.

function Read-EnvironmentVariable {
    <#
    .SYNOPSIS
        Returns the value of an environment variable in one scope.

    .DESCRIPTION
        Calls [System.Environment]::GetEnvironmentVariable. Returns $null when the
        variable is not set. Reads only; changes nothing. Get-MalformedPathEntry uses it for
        the process PATH; the User scope is read with Read-UserEnvironmentValue instead,
        because this expands %VAR% references. Private to PathRepair.

    .PARAMETER Name
        The variable name, such as PATH or BADPATH.

    .PARAMETER Target
        Process (the default), User or Machine.

    .EXAMPLE
        Read-EnvironmentVariable -Name PATH

    .EXAMPLE
        Read-EnvironmentVariable -Name TEMP -Target Process

    .NOTES
        User and Machine scopes are read from the registry, so they exist only on Windows.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [System.EnvironmentVariableTarget]$Target = 'Process'
    )

    [System.Environment]::GetEnvironmentVariable($Name, $Target)
}

function Read-UserEnvironmentValue {
    <#
    .SYNOPSIS
        Returns the raw text and the registry value kind of one User environment variable.

    .DESCRIPTION
        Reads HKCU\Environment\<Name> with RegistryValueOptions.DoNotExpandEnvironmentNames,
        so a %USERPROFILE%-style reference comes back as written, not expanded. Outputs one
        object with Value (the raw string) and Kind (String or ExpandString). A missing value
        gives Value $null and Kind $null, which leaves the kind of a new value to
        Write-UserEnvironmentValue. Throws when the value is not a string kind, or, without
        Key, when this is not Windows. Reads only; changes nothing. Private to PathRepair.

    .PARAMETER Name
        The variable name, such as PATH or BADPATH.

    .PARAMETER Key
        The open registry key to read. Defaults to HKCU\Environment, opened and closed here.
        Tests pass a stand-in object with GetValue and GetValueKind methods.

    .EXAMPLE
        Read-UserEnvironmentValue -Name PATH

    .EXAMPLE
        (Read-UserEnvironmentValue -Name BADPATH).Kind

    .NOTES
        Not [Environment]::GetEnvironmentVariable: on Windows PowerShell 5.1 and
        PowerShell 7 alike it expands the value and loses its kind.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,

        $Key
    )

    $ownKey = $null -eq $Key
    if ($ownKey) {
        if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
            throw 'The User environment scope is stored in the registry, so it exists only on Windows.'
        }
        $Key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $false)
        if ($null -eq $Key) {
            return [pscustomobject]@{ Value = $null; Kind = $null }
        }
    }
    try {
        $value = $Key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($null -eq $value) {
            return [pscustomobject]@{ Value = $null; Kind = $null }
        }
        $kind = [string]$Key.GetValueKind($Name)
        if ($kind -notin 'String', 'ExpandString') {
            throw "HKCU\Environment\$Name is a $kind value, not a string; nothing changed."
        }
        [pscustomobject]@{ Value = [string]$value; Kind = $kind }
    } finally {
        if ($ownKey) { $Key.Dispose() }
    }
}

function Write-UserEnvironmentValue {
    <#
    .SYNOPSIS
        Sets or deletes one User environment variable, with an explicit registry value kind.

    .DESCRIPTION
        Writes Value to HKCU\Environment\<Name> as written (no expansion) with the given
        Kind, so a REG_EXPAND_SZ value keeps its kind and its %VAR% references. Without Kind,
        or with a $null Kind, the value is written as ExpandString when it holds a % and as
        String otherwise; any other Kind throws. A $null or empty Value deletes the variable
        (a missing one is not an error). Throws, without Key, when this is not Windows, so
        nothing is written there. Does not tell running programs: call Send-EnvironmentChange
        after the last write. Outputs nothing. Private to PathRepair.

    .PARAMETER Name
        The variable name.

    .PARAMETER Value
        The new raw value. $null or an empty string deletes the variable.

    .PARAMETER Kind
        String or ExpandString, usually the Kind that Read-UserEnvironmentValue returned.
        $null or empty picks the kind from the value, as for a new variable.

    .PARAMETER Key
        The open, writable registry key to change. Defaults to HKCU\Environment, opened and
        closed here. Tests pass a stand-in object with SetValue and DeleteValue methods.

    .EXAMPLE
        Write-UserEnvironmentValue -Name PATH -Value '%USERPROFILE%\bin;C:\Tools' -Kind ExpandString

    .EXAMPLE
        Write-UserEnvironmentValue -Name PATH_FIX_DATE -Value $null

    .NOTES
        Not [Environment]::SetEnvironmentVariable: it always writes REG_SZ.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Kind,

        $Key
    )

    $ownKey = $null -eq $Key
    if ($ownKey) {
        if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
            throw 'The User environment scope is stored in the registry, so it exists only on Windows.'
        }
        $Key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
    }
    try {
        if ([string]::IsNullOrEmpty($Value)) {
            $Key.DeleteValue($Name, $false)
            return
        }
        if ([string]::IsNullOrEmpty($Kind)) {
            $Kind = if ($Value.Contains('%')) { 'ExpandString' } else { 'String' }
        } elseif ($Kind -notin 'String', 'ExpandString') {
            throw "Kind must be String or ExpandString, not $Kind; HKCU\Environment\$Name not changed."
        }
        $Key.SetValue($Name, $Value, [Microsoft.Win32.RegistryValueKind]$Kind)
    } finally {
        if ($ownKey) { $Key.Dispose() }
    }
}

function Send-EnvironmentChange {
    <#
    .SYNOPSIS
        Tells running programs that the environment variables changed.

    .DESCRIPTION
        Broadcasts WM_SETTINGCHANGE with lParam "Environment" to every top-level window
        (SendMessageTimeout to HWND_BROADCAST, SMTO_ABORTIFHUNG, 1 second per window, as
        .NET uses), as [Environment]::SetEnvironmentVariable does for the User scope, so
        Explorer hands the new PATH to programs started after it. The P/Invoke type is
        compiled with Add-Type once per process, and a re-imported module reuses it. Never
        throws, because it runs after a completed write: when this is not Windows, when
        Add-Type or the call fails, or when the broadcast times out, it writes one warning
        instead. Outputs nothing. Private to PathRepair.

    .EXAMPLE
        Send-EnvironmentChange

    .EXAMPLE
        Write-UserEnvironmentValue -Name PATH -Value $new -Kind $kind; Send-EnvironmentChange

    .NOTES
        In a remote session the broadcast reaches only that session's windows, not the
        user's desktop, so the user's Explorer sees the change at the next sign-in.
    #>
    [CmdletBinding()]
    param ()

    $notTold = 'Running programs were not told about the new environment; programs started from them see it after a sign-in.'
    # The write this follows has already succeeded, so nothing here may throw and report it as failed.
    try {
        if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
            throw 'WM_SETTINGCHANGE exists only on Windows.'
        }
        $native = 'PathRepair.NativeMethods' -as [type]
        if ($null -eq $native) {
            $native = Add-Type -Namespace 'PathRepair' -Name 'NativeMethods' -PassThru -ErrorAction Stop -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
        }
        $hwndBroadcast = [IntPtr]0xffff
        $wmSettingChange = 0x001A
        $smtoAbortIfHung = 0x0002
        $result = [UIntPtr]::Zero
        $sent = $native::SendMessageTimeout($hwndBroadcast, $wmSettingChange, [UIntPtr]::Zero, 'Environment', $smtoAbortIfHung, 1000, [ref]$result)
    } catch {
        Write-Warning "$notTold ($($_.Exception.Message))"
        return
    }
    if ($sent -eq [IntPtr]::Zero) {
        Write-Warning $notTold
    }
}

function Test-PathDirectory {
    <#
    .SYNOPSIS
        Reports whether a PATH entry names an existing directory.

    .DESCRIPTION
        Strips surrounding double quotes, expands %VAR% references for this check only (the
        entry itself is never changed) unless Literal is set, and returns $true when the
        result is an existing file-system directory, $false otherwise (including for a
        blank entry). Uses
        [System.IO.Directory]::Exists, so the path is taken literally (no wildcards, no
        PowerShell drives such as Env: or ~), and a relative entry is resolved against the
        process working directory. Private to PathRepair.

    .PARAMETER Path
        The PATH entry to check.

    .PARAMETER Literal
        Check the entry as written, without expanding %VAR% references: Windows does not
        expand them in a REG_SZ PATH or in a process PATH, which is already expanded.

    .EXAMPLE
        Test-PathDirectory -Path 'C:\Windows\System32'

    .EXAMPLE
        Test-PathDirectory -Path '%USERPROFILE%\bin' -Literal

    .NOTES
        None.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [AllowEmptyString()]
        [string]$Path,

        [switch]$Literal
    )

    $trimmed = $Path.Trim('"')
    if (-not $Literal) {
        $trimmed = [System.Environment]::ExpandEnvironmentVariables($trimmed)
    }
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return $false
    }
    # Not Test-Path: it is provider-aware, so '~', 'Env:' or 'HKCU:\' would count as directories.
    [System.IO.Directory]::Exists($trimmed)
}

function Split-PathValue {
    <#
    .SYNOPSIS
        Splits a PATH value into its entries, keeping quoted semicolons inside an entry.

    .DESCRIPTION
        Splits on every semicolon that is outside double quotes, so 'A;"B;C";D' gives A,
        "B;C" and D. Only a quoted span that covers the whole entry keeps its semicolons:
        any other segment that still holds a semicolon (two stray quotes, 'A";B;C"') is
        split on every semicolon. When the value has an odd number of double quotes,
        quoting cannot be trusted and the value is split on every semicolon instead. Outputs one
        string per entry, including empty ones; an empty value gives one empty entry. Private to
        PathRepair.

    .PARAMETER Value
        The PATH value to split.

    .EXAMPLE
        Split-PathValue -Value 'C:\Windows;"C:\Program Files\Tool";C:\Bin'

    .EXAMPLE
        Split-PathValue -Value $env:PATH

    .NOTES
        None.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [AllowEmptyString()]
        [string]$Value
    )

    if ((($Value -split '"').Count - 1) % 2 -ne 0) {
        return $Value.Split(';')
    }
    $segments = New-Object System.Collections.Generic.List[string]
    $current = New-Object System.Text.StringBuilder
    $inQuotes = $false
    foreach ($char in $Value.ToCharArray()) {
        if ($char -eq '"') {
            $inQuotes = -not $inQuotes
        }
        if ($char -eq ';' -and -not $inQuotes) {
            $segments.Add($current.ToString())
            $null = $current.Clear()
        } else {
            $null = $current.Append($char)
        }
    }
    $segments.Add($current.ToString())

    # Only a quoted span covering the whole entry keeps its semicolons. Two stray quotes
    # (an even total) would otherwise glue every entry between them into one.
    foreach ($segment in $segments) {
        if ($segment.Contains(';') -and $segment -notmatch '^"[^"]*"$') {
            $segment.Split(';')
        } else {
            $segment
        }
    }
}
