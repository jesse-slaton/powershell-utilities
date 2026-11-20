#Requires -Version 5.1
# Encoding check for tracked PowerShell files. Reads raw bytes only and never loads or runs a script.
# UTF-16 files are invisible to byte-based secret scanners (gitleaks and similar), so no tracked
# .ps1, .psm1 or .psd1 may be UTF-16. The check rejects UTF-16 only; it does not prove a file is
# UTF-8 (save as UTF-8, with a BOM when Windows PowerShell 5.1 has to read non-ASCII text).
# Issue #108.

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot

    # No silent skip: without git there is no tracked-file list, so the check cannot run.
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'git is not on PATH. Tests/Encoding.Tests.ps1 needs git ls-files to list tracked PowerShell files.'
    }

    # -z stops git quoting or escaping names with spaces or non-ASCII characters. Windows
    # PowerShell 5.1 still decodes native output with the console code page, so a non-ASCII name
    # can arrive garbled; ReadAllBytes then throws, which fails the test loudly rather than
    # skipping the file. :(icase) also matches upper-case extensions such as .PS1.
    $raw = & git -C $script:repoRoot ls-files -z -- ':(icase)*.ps1' ':(icase)*.psm1' ':(icase)*.psd1'
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files failed with exit code $LASTEXITCODE in '$($script:repoRoot)'."
    }
    $script:trackedFiles = @(($raw -join '') -split "`0" | Where-Object { $_ })
}

Describe 'Tracked PowerShell files are not UTF-16' {
    It 'finds tracked PowerShell files to check' {
        $script:trackedFiles.Count | Should -BeGreaterThan 0 -Because 'git ls-files returned no .ps1, .psm1 or .psd1 files, so the encoding check checked nothing'
    }

    It 'has no UTF-16 byte order mark or NUL byte in any tracked .ps1, .psm1 or .psd1' {
        $offenders = foreach ($relativePath in $script:trackedFiles) {
            $bytes = [System.IO.File]::ReadAllBytes((Join-Path $script:repoRoot $relativePath))
            $reason = $null
            if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { $reason = 'UTF-16LE byte order mark' }
            elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) { $reason = 'UTF-16BE byte order mark' }
            elseif ([Array]::IndexOf($bytes, [byte]0) -ge 0) { $reason = 'NUL byte (UTF-16 without a byte order mark?)' }
            if ($reason) { "$relativePath ($reason)" }
        }

        $message = 'these files must be re-saved as UTF-8 with BOM, keeping their line endings, because secret scanners cannot read UTF-16: ' + (@($offenders) -join '; ')
        @($offenders) | Should -BeNullOrEmpty -Because $message
    }
}
