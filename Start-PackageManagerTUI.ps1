<#
.SYNOPSIS
    Launcher script for Package Manager TUI.

.DESCRIPTION
    Imports the PackageManagerTUI module and starts the interactive interface.

.NOTES
    Script Name : Start-PackageManagerTUI.ps1
    Author      : Jesse Slaton
    Created     : 2025-10-15
    Version     : 1.0.0
    Requires    : PowerShell 5.1+, winget

.EXAMPLE
    .\Start-PackageManagerTUI.ps1
    Launches the Package Manager TUI.
#>

[CmdletBinding()]
param()

# Import the module
$modulePath = Join-Path $PSScriptRoot 'Modules\PackageManagerTUI\PackageManagerTUI.psd1'

if (-not (Test-Path $modulePath)) {
    Write-Error "PackageManagerTUI module not found at: $modulePath"
    exit 1
}

Import-Module $modulePath -Force

# Start the TUI
Start-PackageManagerTUI
