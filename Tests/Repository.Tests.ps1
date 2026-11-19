#Requires -Version 5.1
# Repository hygiene checks. These read file names only and never load or run any script.

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
