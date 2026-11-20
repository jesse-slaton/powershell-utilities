<#
.SYNOPSIS
    Installs the pinned Pester and PSScriptAnalyzer versions used by this test suite.

.DESCRIPTION
    Installs Pester and PSScriptAnalyzer for the current user from the PowerShell Gallery
    unless the pinned versions are already present. CI runs this before Invoke-Pester so
    local and CI runs use the same versions.

.PARAMETER PesterVersion
    Pester version to install. The suite uses Pester 5 syntax.

.PARAMETER ScriptAnalyzerVersion
    PSScriptAnalyzer version to install.

.EXAMPLE
    ./Tests/Install-TestDependencies.ps1

    Installs the pinned versions if they are missing.

.EXAMPLE
    ./Tests/Install-TestDependencies.ps1 -PesterVersion 5.7.1

    Installs a different Pester 5 release, for example to try an upgrade.

.NOTES
    Needs network access to the PowerShell Gallery. Installs to the CurrentUser scope,
    so no admin rights are required.
#>
[CmdletBinding()]
param(
    [version]$PesterVersion = '5.6.1',
    [version]$ScriptAnalyzerVersion = '1.23.0'
)

# No session-wide $ErrorActionPreference: the script is also dot-sourced, and a Stop set
# here would leak into the caller's Pester run (CI runs the suite with the default
# Continue). Each call that must stop on failure says so with -ErrorAction Stop.

foreach ($module in @(
        @{ Name = 'Pester'; Version = $PesterVersion }
        @{ Name = 'PSScriptAnalyzer'; Version = $ScriptAnalyzerVersion }
    )) {
    if (Get-Module -ListAvailable -Name $module.Name | Where-Object Version -EQ $module.Version) {
        Write-Host "$($module.Name) $($module.Version) already installed"
        continue
    }
    Write-Host "Installing $($module.Name) $($module.Version)"
    # -SkipPublisherCheck: Windows PowerShell 5.1 ships an old, differently signed Pester 3.4.
    Install-Module -Name $module.Name -RequiredVersion $module.Version -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber -ErrorAction Stop
}

# Load the pinned versions into this session so a dot-sourced run (. ./Tests/Install-TestDependencies.ps1)
# uses them instead of whichever version autoloads first. CI imports them again in its own test step.
foreach ($module in @(
        @{ Name = 'Pester'; Version = $PesterVersion }
        @{ Name = 'PSScriptAnalyzer'; Version = $ScriptAnalyzerVersion }
    )) {
    Get-Module -Name $module.Name | Where-Object Version -NE $module.Version | Remove-Module -Force -ErrorAction Stop
    Import-Module -Name $module.Name -RequiredVersion $module.Version -Force -Global -ErrorAction Stop
}
