#Requires -Version 5.1
# Repository hygiene checks. These read file names (and Tests/README.md) only and never load or run any script.

BeforeDiscovery {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $unitTests = Get-ChildItem -Path (Join-Path $repoRoot 'Tests/Unit') -Filter '*.Tests.ps1' -File -ErrorAction SilentlyContinue
    $script:testCases = foreach ($test in $unitTests) {
        @{ TestFile = $test.Name; TargetName = $test.Name -replace '\.Tests\.ps1$', '' }
    }
}

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $script:targetNames = @(
        Get-ChildItem -Path (Join-Path $repoRoot 'Scripts'), (Join-Path $repoRoot 'Modules') -Recurse -File -Include '*.ps1', '*.psm1' |
            Where-Object { $_.Name -notmatch '\.Tests\.psm?1$' } |
            ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) }
    )
}

Describe 'Tests/Unit has no orphaned test files' {
    It '<TestFile> targets an existing file under Scripts/ or Modules/' -TestCases $script:testCases {
        param($TestFile, $TargetName)
        $script:targetNames | Should -Contain $TargetName -Because "$TestFile has no matching .ps1 or .psm1 under Scripts/ or Modules/; delete the test or restore the script"
    }
}

Describe 'Tests/README.md lists every test file' {
    It 'names each file directly under Tests/ in its Layout table' {
        $testsRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'Tests'
        $readme = Get-Content -LiteralPath (Join-Path $testsRoot 'README.md') -Raw
        # Tracked files only, so a stray untracked file (a test-results.xml, an editor backup) cannot fail this.
        $names = $null
        if (Get-Command git -CommandType Application -ErrorAction SilentlyContinue) {
            $raw = & git -C (Split-Path -Parent $PSScriptRoot) ls-files -z -- Tests/ 2>$null
            if ($LASTEXITCODE -eq 0) {
                $names = @("$raw" -split "`0" | Where-Object { $_ -match '^Tests/[^/]+$' } | ForEach-Object { $_.Substring(6) })
            }
        }
        if ($null -eq $names) {
            # No git or not a work tree: fall back to the script files, which an editor or Pester never writes stray copies of.
            $names = @(Get-ChildItem -LiteralPath $testsRoot -File | Where-Object { $_.Extension -in '.ps1', '.psm1' } | ForEach-Object { $_.Name })
        }
        $missing = @($names | Where-Object { $_ -ne 'README.md' -and -not $readme.Contains("| ``$_`` |") })
        $missing | Should -BeNullOrEmpty -Because 'every file in Tests/ needs a row in the README Layout table'
    }
}
