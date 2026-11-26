<#
.SYNOPSIS
    Outputs the hash of a file, with the path and algorithm supplied as Tanium parameters.

.DESCRIPTION
    URL-decodes the FilePath value (percent escapes, and '+' as a space), and if that
    path exists, outputs (Get-FileHash -Algorithm <HashType>).Hash, the hash as an
    uppercase hex string. If the path does not exist, writes the error "Could not get
    the file hash" and exits with code 1. Read-only.

    Runs in-process; it never relaunches itself in another PowerShell. When a 32-bit
    host on 64-bit Windows is asked for a file under %WINDIR%\System32, the path is
    read through %WINDIR%\Sysnative so the file system redirector does not swap in the
    SysWOW64 copy. Forward slashes and a leading \\?\ prefix are accepted in that path.

    The script has no param() block. FilePath and HashType are Tanium package
    parameters: Tanium replaces the '||FilePath||' and '||HashType||' tokens before the
    script runs. HashType must be an algorithm Get-FileHash accepts, such as SHA256 or
    MD5.

.EXAMPLE
    .\TaniumFileHash-Package.ps1

    Run by Tanium as a package with FilePath and HashType set; outputs <HashValue>.

.NOTES
    Requires the Tanium Client to substitute the ||FilePath|| and ||HashType||
    parameters; run outside Tanium, the literal tokens are used and the path is not
    found. Windows PowerShell 5.1 or PowerShell 7. Reading the file needs whatever
    rights the file requires.

    Exit codes: 0 when the hash is written; 1 when it is not (the path does not exist
    or cannot be hashed). The exit is explicit because under -File a written error
    alone leaves the exit code at 0, which Tanium would report as success.

    The '||FilePath||' token sits inside single quotes, so '$' and '`' in the value are
    taken literally. An apostrophe in the substituted value would end the string and
    break the script, so the value must arrive URL-encoded (an apostrophe as %27); a
    raw apostrophe is not supported.
#>

function ConvertFrom-TaniumUrlEncoding {
    <#
    .SYNOPSIS
        Decodes a URL-encoded Tanium parameter value: '+' becomes a space, then percent escapes are decoded.

    .NOTES
        Unlike HttpUtility.UrlDecode, the non-standard %uXXXX escape is
        not decoded ('%u0041' stays literal instead of becoming 'A'). Tanium is not
        expected to emit %u escapes, so standard %XX UTF-8 escapes are all that is
        handled.
    #>
    param([string]$Value)

    [uri]::UnescapeDataString($Value.Replace('+', ' '))
}

function Resolve-NativeFilePath {
    <#
    .SYNOPSIS
        Rewrites a %WINDIR%\System32 path to %WINDIR%\Sysnative when the host is 32-bit on 64-bit Windows.

    .DESCRIPTION
        The comparison accepts '/' as a separator and ignores a leading \\?\ prefix, so
        every spelling of a System32 path is read from the native folder. A rewritten
        path uses backslashes and no \\?\ prefix; any other path is returned unchanged.

    .PARAMETER Path
        File path to resolve.

    .PARAMETER WindowsDirectory
        The Windows folder. Defaults to $env:WINDIR.

    .PARAMETER Wow64
        True when the host is a 32-bit process on 64-bit Windows. Defaults to whether
        PROCESSOR_ARCHITEW6432 is set.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$WindowsDirectory = $env:WINDIR,

        [bool]$Wow64 = [bool]$env:PROCESSOR_ARCHITEW6432
    )

    if (-not $Wow64 -or -not $WindowsDirectory) { return $Path }
    $Windows = $WindowsDirectory.Replace('/', '\').TrimEnd('\')
    $System32 = $Windows + '\System32'
    $Candidate = $Path.Replace('/', '\')
    if ($Candidate.StartsWith('\\?\')) { $Candidate = $Candidate.Substring(4) }
    if ($Candidate -eq $System32 -or $Candidate.StartsWith($System32 + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Windows + '\Sysnative' + $Candidate.Substring($System32.Length)
    }
    $Path
}

function Get-TaniumFileHash {
    <#
    .SYNOPSIS
        Writes the hash of the file a URL-encoded Tanium path names, or an error when it does not exist.

    .PARAMETER EncodedPath
        The URL-encoded file path, as Tanium substitutes it.

    .PARAMETER HashType
        Get-FileHash algorithm, such as SHA256.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$EncodedPath,

        [Parameter(Mandatory)]
        [string]$HashType
    )

    $FilePath = Resolve-NativeFilePath -Path (ConvertFrom-TaniumUrlEncoding -Value $EncodedPath)
    if (Test-Path -LiteralPath $FilePath -PathType Leaf) {
        (Get-FileHash -LiteralPath $FilePath -Algorithm $HashType).Hash
    }
    else {
        Write-Error "Could not get the file hash"
    }
}

Get-TaniumFileHash -EncodedPath '||FilePath||' -HashType '||HashType||' -ErrorVariable HashError
if ($HashError) { exit 1 }
