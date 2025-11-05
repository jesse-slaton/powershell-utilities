<#
.SYNOPSIS
    Analyzes comment-based help coverage across PowerShell scripts in the repository.

.DESCRIPTION
    This script scans all .ps1 files in the repository and categorizes them based on
    their comment-based help documentation status. It identifies scripts with complete
    help, partial help, and no help documentation.

.EXAMPLE
    .\Analyze-HelpCoverage.ps1
    Analyzes all scripts and displays a summary of help coverage.

.NOTES
    Author: Generated for Issue #4
    Purpose: Track progress of adding comment-based help to all scripts
#>

[CmdletBinding()]
param()

$RepoRoot = $PSScriptRoot
$AllScripts = Get-ChildItem -Path $RepoRoot -Filter "*.ps1" -Recurse | Where-Object {
    $_.FullName -notmatch '\\\.git\\'
}

$Results = @{
    WithCompleteHelp = @()
    WithPartialHelp = @()
    WithoutHelp = @()
}

foreach ($Script in $AllScripts) {
    $Content = Get-Content -Path $Script.FullName -Raw

    # Check for comment-based help block
    $HasHelpBlock = $Content -match '(?ms)<#.*?\.SYNOPSIS.*?#>'

    if ($HasHelpBlock) {
        # Check for complete help (must have SYNOPSIS, DESCRIPTION, and at least one EXAMPLE)
        $HasSynopsis = $Content -match '\.SYNOPSIS'
        $HasDescription = $Content -match '\.DESCRIPTION'
        $HasExample = $Content -match '\.EXAMPLE'
        $HasParameters = $Content -match '\.PARAMETER'

        if ($HasSynopsis -and $HasDescription -and $HasExample) {
            $Results.WithCompleteHelp += $Script
        } else {
            $Results.WithPartialHelp += $Script
        }
    } else {
        $Results.WithoutHelp += $Script
    }
}

# Display summary
$TotalScripts = $AllScripts.Count
$CompleteCount = $Results.WithCompleteHelp.Count
$PartialCount = $Results.WithPartialHelp.Count
$NoHelpCount = $Results.WithoutHelp.Count
$CoveredCount = $CompleteCount + $PartialCount

Write-Host "`n=== PowerShell Help Coverage Analysis ===" -ForegroundColor Cyan
Write-Host "Total Scripts: $TotalScripts" -ForegroundColor White
Write-Host "With Complete Help: $CompleteCount ($([math]::Round($CompleteCount/$TotalScripts*100, 1))%)" -ForegroundColor Green
Write-Host "With Partial Help: $PartialCount ($([math]::Round($PartialCount/$TotalScripts*100, 1))%)" -ForegroundColor Yellow
Write-Host "Without Help: $NoHelpCount ($([math]::Round($NoHelpCount/$TotalScripts*100, 1))%)" -ForegroundColor Red
Write-Host "Overall Coverage: $CoveredCount / $TotalScripts ($([math]::Round($CoveredCount/$TotalScripts*100, 1))%)`n" -ForegroundColor Cyan

# Group scripts without help by directory
Write-Host "`n=== Scripts Without Help (by directory) ===" -ForegroundColor Yellow
$NoHelpByDir = $Results.WithoutHelp | Group-Object {
    $_.FullName.Replace($RepoRoot, '').Split([IO.Path]::DirectorySeparatorChar)[1..2] -join '\'
} | Sort-Object Count -Descending

foreach ($Group in $NoHelpByDir) {
    Write-Host "$($Group.Name): $($Group.Count) scripts" -ForegroundColor Yellow
}

# Export detailed results
$ExportPath = Join-Path $RepoRoot "help-coverage-report.json"
$ExportData = @{
    TotalScripts = $TotalScripts
    CompleteHelp = $Results.WithCompleteHelp | ForEach-Object { $_.FullName.Replace($RepoRoot, '.') }
    PartialHelp = $Results.WithPartialHelp | ForEach-Object { $_.FullName.Replace($RepoRoot, '.') }
    NoHelp = $Results.WithoutHelp | ForEach-Object { $_.FullName.Replace($RepoRoot, '.') }
}

$ExportData | ConvertTo-Json -Depth 3 | Set-Content -Path $ExportPath
Write-Host "`nDetailed report exported to: $ExportPath" -ForegroundColor Green

# Return results for pipeline
return $Results
