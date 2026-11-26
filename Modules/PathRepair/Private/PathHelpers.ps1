# Thin wrappers around environment-variable and directory checks, plus the one PATH
# splitter. Every such call in PathRepair goes through these functions so tests can mock
# them on any OS (User and Machine environment scopes exist only on Windows). Each one is
# self-contained, calling nothing else in the module, so its definition can be sent to a
# remote session.

function Read-EnvironmentVariable {
    <#
    .SYNOPSIS
        Returns the value of an environment variable in one scope.

    .DESCRIPTION
        Calls [System.Environment]::GetEnvironmentVariable. Returns $null when the
        variable is not set. Reads only; changes nothing. Private to PathRepair.

    .PARAMETER Name
        The variable name, such as PATH or BADPATH.

    .PARAMETER Target
        Process (the default), User or Machine.

    .EXAMPLE
        Read-EnvironmentVariable -Name PATH -Target User

    .EXAMPLE
        Read-EnvironmentVariable -Name PATH

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

function Write-EnvironmentVariable {
    <#
    .SYNOPSIS
        Sets or deletes an environment variable in one scope.

    .DESCRIPTION
        Calls [System.Environment]::SetEnvironmentVariable. A $null or empty Value
        deletes the variable. Outputs nothing. Private to PathRepair.

    .PARAMETER Name
        The variable name.

    .PARAMETER Value
        The new value. $null or an empty string deletes the variable.

    .PARAMETER Target
        User (the default), Machine or Process.

    .EXAMPLE
        Write-EnvironmentVariable -Name BADPATH -Value $oldPath -Target User

    .EXAMPLE
        Write-EnvironmentVariable -Name PATH_FIX_DATE -Value $null

    .NOTES
        Writing the Machine scope needs administrator rights. User and Machine scopes
        exist only on Windows.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [AllowNull()]
        [AllowEmptyString()]
        $Value,

        [System.EnvironmentVariableTarget]$Target = 'User'
    )

    [System.Environment]::SetEnvironmentVariable($Name, $Value, $Target)
}

function Test-PathDirectory {
    <#
    .SYNOPSIS
        Reports whether a PATH entry names an existing directory.

    .DESCRIPTION
        Strips surrounding double quotes and returns $true when the result is an existing
        file-system directory, $false otherwise (including for a blank entry). Uses
        [System.IO.Directory]::Exists, so the path is taken literally (no wildcards, no
        PowerShell drives such as Env: or ~), and a relative entry is resolved against the
        process working directory. Private to PathRepair.

    .PARAMETER Path
        The PATH entry to check.

    .EXAMPLE
        Test-PathDirectory -Path 'C:\Windows\System32'

    .EXAMPLE
        Test-PathDirectory -Path '"C:\Program Files\Git\cmd"'

    .NOTES
        None.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [AllowEmptyString()]
        [string]$Path
    )

    $trimmed = $Path.Trim('"')
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
