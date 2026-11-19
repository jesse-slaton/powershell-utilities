#Requires -Version 5.1
# Smoke tests for every tracked script and module under Scripts/ and Modules/.
# Files are parsed and analyzed only; nothing is dot-sourced or executed.

BeforeDiscovery {
    Import-Module (Join-Path $PSScriptRoot 'TestHelpers.psm1') -Force
    $repoRoot = Get-RepoRoot
    $script:files = foreach ($file in Get-TrackedScript) {
        @{
            Path         = $file.FullName
            RelativePath = $file.FullName.Substring($repoRoot.Length + 1) -replace '\\', '/'
        }
    }
    $script:analyzerAvailable = [bool](Get-Module -ListAvailable -Name PSScriptAnalyzer)
}

Describe 'Smoke: <RelativePath>' -ForEach $script:files {
    It 'parses with no syntax errors' {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
        $errors | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" } | Should -BeNullOrEmpty
    }

    It 'has no PSScriptAnalyzer Error-severity findings' -Skip:(-not $script:analyzerAvailable) {
        $findings = Invoke-ScriptAnalyzer -Path $Path -Severity Error
        $findings | ForEach-Object { "line $($_.Line): $($_.RuleName): $($_.Message)" } | Should -BeNullOrEmpty
    }
}
