#Requires -Version 5.1
# Encoding check for tracked PowerShell files. Reads raw bytes only and never loads or runs a script.
# UTF-16 files are invisible to byte-based secret scanners (gitleaks and similar), so no tracked
# .ps1, .psm1 or .psd1 may be UTF-16. Every such file must be valid UTF-8 (with a BOM when Windows
# PowerShell 5.1 has to read non-ASCII text, which the test enforces) and hold no control character other than tab, LF, FF
# and CR. That rejects UTF-16 with or without a BOM: ASCII text in UTF-16 has NUL bytes, and other
# BOM-less UTF-16 is either invalid UTF-8 or holds control bytes (U+0101 is the bytes 01 01).
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

Describe 'Tracked PowerShell files are UTF-8, not UTF-16' {
    It 'finds tracked PowerShell files to check' {
        $script:trackedFiles.Count | Should -BeGreaterThan 0 -Because 'git ls-files returned no .ps1, .psm1 or .psd1 files, so the encoding check checked nothing'
    }

    It 'has only valid UTF-8 text, with no UTF-16 byte order mark or control byte, in any tracked .ps1, .psm1 or .psd1' {
        # Strict decoder: throws on invalid UTF-8 instead of substituting U+FFFD. New-Object, not
        # ::new(), so the test also runs on Windows PowerShell 5.1.
        $strictUtf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false, $true
        $offenders = foreach ($relativePath in $script:trackedFiles) {
            $bytes = [System.IO.File]::ReadAllBytes((Join-Path $script:repoRoot $relativePath))
            $reason = $null
            if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { $reason = 'UTF-16LE byte order mark' }
            elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) { $reason = 'UTF-16BE byte order mark' }
            else {
                $text = $null
                try { $text = $strictUtf8.GetString($bytes) }
                catch [System.Text.DecoderFallbackException] { $reason = 'not valid UTF-8 (UTF-16 without a byte order mark?)' }
                # A byte below 0x20 is never part of a multi-byte UTF-8 sequence, so matching the
                # decoded text finds every such byte. NUL is the usual sign of BOM-less UTF-16.
                if ($null -ne $text -and $text -match '[\x00-\x08\x0B\x0E-\x1F]') {
                    $reason = 'control character other than tab, LF, FF or CR (UTF-16 without a byte order mark?)'
                }
                # Windows PowerShell 5.1 reads a BOM-less file in the system code page, so non-ASCII
                # UTF-8 text needs the BOM (EF BB BF). Pure ASCII reads the same either way.
                elseif ($null -ne $text) {
                    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
                    $start = 0
                    if ($hasBom) { $start = 3 }
                    $nonAscii = $false
                    for ($i = $start; $i -lt $bytes.Length; $i++) { if ($bytes[$i] -gt 0x7F) { $nonAscii = $true; break } }
                    if ($nonAscii -and -not $hasBom) { $reason = 'non-ASCII UTF-8 text without a byte order mark (Windows PowerShell 5.1 misreads it)' }
                }
            }
            if ($reason) { "$relativePath ($reason)" }
        }

        $message = 'these files must be re-saved as UTF-8 with BOM, keeping their line endings (secret scanners cannot read UTF-16, and Windows PowerShell 5.1 misreads BOM-less non-ASCII UTF-8): ' + (@($offenders) -join '; ')
        @($offenders) | Should -BeNullOrEmpty -Because $message
    }
}
