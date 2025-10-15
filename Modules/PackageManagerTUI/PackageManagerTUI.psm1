<#
.SYNOPSIS
    Package Manager TUI - Terminal interface for managing winget packages and PowerShell modules.

.DESCRIPTION
    Provides a text-based user interface for discovering, installing, updating, and removing
    packages from winget and PowerShell Gallery. Inspired by UniGetUI.

.NOTES
    Module Name : PackageManagerTUI
    Author      : Jesse Slaton
    Created     : 2025-10-15
    Version     : 1.0.0
    Requires    : PowerShell 5.1+, winget

.EXAMPLE
    Start-PackageManagerTUI
    Launches the interactive package manager interface.
#>

#Requires -Version 5.1

# Module-level variables
$script:CurrentTab = 0
$script:Tabs = @('Discover', 'Updates', 'Installed', 'Settings')
$script:SelectedIndex = 0
$script:ScrollOffset = 0
$script:SearchQuery = ""
$script:PackageList = @()
$script:Settings = @{
    EnabledSources = @('winget', 'PSGallery')
    AutoRefresh = $true
    PageSize = 15
}

#region Core TUI Functions

function Start-PackageManagerTUI {
    <#
    .SYNOPSIS
        Starts the Package Manager TUI.

    .DESCRIPTION
        Launches the interactive terminal interface for package management.

    .EXAMPLE
        Start-PackageManagerTUI
    #>
    [CmdletBinding()]
    param()

    # Initialize
    Initialize-TUI

    # Main loop
    $running = $true
    while ($running) {
        Show-TUI
        $key = [Console]::ReadKey($true)

        switch ($key.Key) {
            'Tab' {
                $script:CurrentTab = ($script:CurrentTab + 1) % $script:Tabs.Count
                $script:SelectedIndex = 0
                $script:ScrollOffset = 0
            }
            'LeftArrow' {
                if ($script:CurrentTab -gt 0) {
                    $script:CurrentTab--
                    $script:SelectedIndex = 0
                    $script:ScrollOffset = 0
                }
            }
            'RightArrow' {
                if ($script:CurrentTab -lt ($script:Tabs.Count - 1)) {
                    $script:CurrentTab++
                    $script:SelectedIndex = 0
                    $script:ScrollOffset = 0
                }
            }
            'UpArrow' {
                if ($script:SelectedIndex -gt 0) {
                    $script:SelectedIndex--
                    if ($script:SelectedIndex < $script:ScrollOffset) {
                        $script:ScrollOffset = $script:SelectedIndex
                    }
                }
            }
            'DownArrow' {
                $maxIndex = ($script:PackageList.Count - 1)
                if ($script:SelectedIndex -lt $maxIndex) {
                    $script:SelectedIndex++
                    if ($script:SelectedIndex >= ($script:ScrollOffset + $script:Settings.PageSize)) {
                        $script:ScrollOffset++
                    }
                }
            }
            'Enter' {
                Invoke-CurrentAction
            }
            'F' {
                if ($key.Modifiers -band [ConsoleModifiers]::Control) {
                    # Ctrl+F: Search
                    Start-SearchMode
                }
            }
            'R' {
                if ($key.Modifiers -band [ConsoleModifiers]::Control) {
                    # Ctrl+R: Refresh
                    Refresh-CurrentTab
                }
            }
            'Q' {
                $running = $false
            }
            'Escape' {
                $running = $false
            }
        }
    }

    Clear-Host
    Write-Host "Package Manager TUI closed." -ForegroundColor Green
}

function Initialize-TUI {
    [CmdletBinding()]
    param()

    # Verify winget is available
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warning "winget is not installed. Some features will be unavailable."
    }

    # Load settings from file if exists
    $settingsPath = Join-Path $env:USERPROFILE '.packagemanagertui\settings.json'
    if (Test-Path $settingsPath) {
        try {
            $loadedSettings = Get-Content $settingsPath -Raw | ConvertFrom-Json
            $script:Settings = $loadedSettings
        }
        catch {
            Write-Warning "Failed to load settings: $_"
        }
    }

    # Set console size if possible
    try {
        if ($Host.UI.RawUI.WindowSize.Width -lt 120) {
            $size = $Host.UI.RawUI.WindowSize
            $size.Width = 120
            $Host.UI.RawUI.WindowSize = $size
        }
    }
    catch {
        # Ignore if can't resize
    }

    # Initial data load
    Refresh-CurrentTab
}

function Show-TUI {
    [CmdletBinding()]
    param()

    Clear-Host

    # Header
    Write-Host "╔═══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║" -ForegroundColor Cyan -NoNewline
    Write-Host "                         Package Manager TUI v1.0.0                           " -ForegroundColor White -NoNewline
    Write-Host "║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # Tab bar
    Write-Host "  " -NoNewline
    for ($i = 0; $i -lt $script:Tabs.Count; $i++) {
        if ($i -eq $script:CurrentTab) {
            Write-Host "[ $($script:Tabs[$i]) ]" -ForegroundColor Black -BackgroundColor White -NoNewline
        } else {
            Write-Host "  $($script:Tabs[$i])  " -ForegroundColor Gray -NoNewline
        }
        Write-Host "  " -NoNewline
    }
    Write-Host ""
    Write-Host ("─" * 80) -ForegroundColor DarkGray
    Write-Host ""

    # Tab content
    switch ($script:Tabs[$script:CurrentTab]) {
        'Discover' { Show-DiscoverTab }
        'Updates' { Show-UpdatesTab }
        'Installed' { Show-InstalledTab }
        'Settings' { Show-SettingsTab }
    }

    # Footer
    Write-Host ""
    Write-Host ("─" * 80) -ForegroundColor DarkGray
    Write-Host "  Tab/←→: Switch tabs  |  ↑↓: Navigate  |  Enter: Select  |  Ctrl+F: Search  |  Ctrl+R: Refresh  |  Q/Esc: Quit" -ForegroundColor DarkGray
}

#endregion

#region Tab Display Functions

function Show-DiscoverTab {
    [CmdletBinding()]
    param()

    Write-Host "  Discover Packages" -ForegroundColor Yellow
    Write-Host "  Search and install packages from winget and PowerShell Gallery" -ForegroundColor DarkGray
    Write-Host ""

    if ($script:SearchQuery) {
        Write-Host "  Search: " -NoNewline -ForegroundColor Cyan
        Write-Host $script:SearchQuery -ForegroundColor White
        Write-Host ""
    }

    if ($script:PackageList.Count -eq 0) {
        Write-Host "  No packages found. Press Ctrl+F to search." -ForegroundColor DarkGray
        return
    }

    Show-PackageList -Action "Install"
}

function Show-UpdatesTab {
    [CmdletBinding()]
    param()

    Write-Host "  Software Updates" -ForegroundColor Yellow
    Write-Host "  Available updates for installed packages" -ForegroundColor DarkGray
    Write-Host ""

    if ($script:PackageList.Count -eq 0) {
        Write-Host "  Loading updates..." -ForegroundColor DarkGray
        return
    }

    Show-PackageList -Action "Update"
}

function Show-InstalledTab {
    [CmdletBinding()]
    param()

    Write-Host "  Installed Packages" -ForegroundColor Yellow
    Write-Host "  Manage installed packages" -ForegroundColor DarkGray
    Write-Host ""

    if ($script:PackageList.Count -eq 0) {
        Write-Host "  Loading installed packages..." -ForegroundColor DarkGray
        return
    }

    Show-PackageList -Action "Uninstall"
}

function Show-SettingsTab {
    [CmdletBinding()]
    param()

    Write-Host "  Settings" -ForegroundColor Yellow
    Write-Host ""

    Write-Host "  Package Sources:" -ForegroundColor Cyan
    foreach ($source in @('winget', 'PSGallery')) {
        $enabled = $script:Settings.EnabledSources -contains $source
        $indicator = if ($enabled) { "[X]" } else { "[ ]" }
        Write-Host "    $indicator $source" -ForegroundColor $(if ($enabled) { "Green" } else { "DarkGray" })
    }

    Write-Host ""
    Write-Host "  Display Options:" -ForegroundColor Cyan
    Write-Host "    Page Size: $($script:Settings.PageSize)" -ForegroundColor White
    Write-Host "    Auto Refresh: $($script:Settings.AutoRefresh)" -ForegroundColor White

    Write-Host ""
    Write-Host "  Settings are saved to:" -ForegroundColor DarkGray
    Write-Host "    $env:USERPROFILE\.packagemanagertui\settings.json" -ForegroundColor DarkGray
}

function Show-PackageList {
    [CmdletBinding()]
    param(
        [string]$Action
    )

    $visibleStart = $script:ScrollOffset
    $visibleEnd = [Math]::Min($visibleStart + $script:Settings.PageSize - 1, $script:PackageList.Count - 1)

    Write-Host "  " -NoNewline
    Write-Host "Package Name".PadRight(40) -ForegroundColor Cyan -NoNewline
    Write-Host "Version".PadRight(15) -ForegroundColor Cyan -NoNewline
    Write-Host "Source".PadRight(15) -ForegroundColor Cyan
    Write-Host "  " -NoNewline
    Write-Host ("-" * 70) -ForegroundColor DarkGray

    for ($i = $visibleStart; $i -le $visibleEnd; $i++) {
        $pkg = $script:PackageList[$i]
        $isSelected = ($i -eq $script:SelectedIndex)

        if ($isSelected) {
            Write-Host "▶ " -ForegroundColor Yellow -NoNewline
            $bgColor = "DarkGray"
            $fgColor = "White"
        } else {
            Write-Host "  " -NoNewline
            $bgColor = "Black"
            $fgColor = "Gray"
        }

        Write-Host $pkg.Name.PadRight(40).Substring(0, [Math]::Min(40, $pkg.Name.Length)) -ForegroundColor $fgColor -NoNewline
        Write-Host $pkg.Version.PadRight(15).Substring(0, [Math]::Min(15, $pkg.Version.Length)) -ForegroundColor $fgColor -NoNewline
        Write-Host $pkg.Source.PadRight(15) -ForegroundColor $fgColor
    }

    # Show scroll indicator
    if ($script:PackageList.Count > $script:Settings.PageSize) {
        Write-Host ""
        Write-Host "  Showing $($visibleStart + 1)-$($visibleEnd + 1) of $($script:PackageList.Count)" -ForegroundColor DarkGray
    }
}

#endregion

#region Action Functions

function Invoke-CurrentAction {
    [CmdletBinding()]
    param()

    if ($script:PackageList.Count -eq 0) { return }

    $package = $script:PackageList[$script:SelectedIndex]

    switch ($script:Tabs[$script:CurrentTab]) {
        'Discover' {
            Install-SelectedPackage $package
        }
        'Updates' {
            Update-SelectedPackage $package
        }
        'Installed' {
            Uninstall-SelectedPackage $package
        }
    }
}

function Start-SearchMode {
    [CmdletBinding()]
    param()

    # Only allow search in Discover tab
    if ($script:Tabs[$script:CurrentTab] -ne 'Discover') { return }

    # Show search prompt
    $cursorTop = [Console]::CursorTop
    Write-Host ""
    Write-Host "  Search: " -NoNewline -ForegroundColor Cyan
    $query = Read-Host

    if ($query) {
        $script:SearchQuery = $query
        $script:SelectedIndex = 0
        $script:ScrollOffset = 0
        Search-Packages
    }
}

function Refresh-CurrentTab {
    [CmdletBinding()]
    param()

    $script:PackageList = @()

    switch ($script:Tabs[$script:CurrentTab]) {
        'Discover' {
            if ($script:SearchQuery) {
                Search-Packages
            }
        }
        'Updates' {
            Get-AvailableUpdates
        }
        'Installed' {
            Get-InstalledPackages
        }
    }
}

#endregion

#region Package Operations

function Search-Packages {
    [CmdletBinding()]
    param()

    $script:PackageList = @()

    # Search winget
    if ($script:Settings.EnabledSources -contains 'winget') {
        try {
            $wingetResults = winget search $script:SearchQuery --accept-source-agreements 2>$null |
                Select-Object -Skip 2 |
                Where-Object { $_ -match '\S' }

            foreach ($line in $wingetResults) {
                if ($line -match '^(\S+)\s+(\S+)\s+(\S+)') {
                    $script:PackageList += [PSCustomObject]@{
                        Name = $matches[1]
                        Version = $matches[2]
                        Source = 'winget'
                        Id = $matches[1]
                    }
                }
            }
        }
        catch {
            # Ignore errors
        }
    }

    # Search PowerShell Gallery
    if ($script:Settings.EnabledSources -contains 'PSGallery') {
        try {
            $psResults = Find-Module -Name "*$($script:SearchQuery)*" -ErrorAction SilentlyContinue |
                Select-Object -First 20

            foreach ($module in $psResults) {
                $script:PackageList += [PSCustomObject]@{
                    Name = $module.Name
                    Version = $module.Version
                    Source = 'PSGallery'
                    Id = $module.Name
                }
            }
        }
        catch {
            # Ignore errors
        }
    }
}

function Get-AvailableUpdates {
    [CmdletBinding()]
    param()

    $script:PackageList = @()

    # Check winget updates
    if ($script:Settings.EnabledSources -contains 'winget') {
        try {
            $updates = winget upgrade --accept-source-agreements 2>$null |
                Select-Object -Skip 2 |
                Where-Object { $_ -match '\S' -and $_ -notmatch 'upgrades available' }

            foreach ($line in $updates) {
                if ($line -match '^(\S+)\s+(\S+)\s+(\S+)') {
                    $script:PackageList += [PSCustomObject]@{
                        Name = $matches[1]
                        Version = "$($matches[2]) → $($matches[3])"
                        Source = 'winget'
                        Id = $matches[1]
                    }
                }
            }
        }
        catch {
            # Ignore errors
        }
    }

    # Check PowerShell module updates
    if ($script:Settings.EnabledSources -contains 'PSGallery') {
        try {
            $installed = Get-InstalledModule -ErrorAction SilentlyContinue
            foreach ($module in $installed) {
                $latest = Find-Module -Name $module.Name -ErrorAction SilentlyContinue
                if ($latest -and ([version]$latest.Version -gt [version]$module.Version)) {
                    $script:PackageList += [PSCustomObject]@{
                        Name = $module.Name
                        Version = "$($module.Version) → $($latest.Version)"
                        Source = 'PSGallery'
                        Id = $module.Name
                    }
                }
            }
        }
        catch {
            # Ignore errors
        }
    }
}

function Get-InstalledPackages {
    [CmdletBinding()]
    param()

    $script:PackageList = @()

    # Get winget installed packages
    if ($script:Settings.EnabledSources -contains 'winget') {
        try {
            $installed = winget list --accept-source-agreements 2>$null |
                Select-Object -Skip 2 |
                Where-Object { $_ -match '\S' }

            foreach ($line in $installed) {
                if ($line -match '^(\S+)\s+(\S+)') {
                    $script:PackageList += [PSCustomObject]@{
                        Name = $matches[1]
                        Version = $matches[2]
                        Source = 'winget'
                        Id = $matches[1]
                    }
                }
            }
        }
        catch {
            # Ignore errors
        }
    }

    # Get installed PowerShell modules
    if ($script:Settings.EnabledSources -contains 'PSGallery') {
        try {
            $modules = Get-InstalledModule -ErrorAction SilentlyContinue
            foreach ($module in $modules) {
                $script:PackageList += [PSCustomObject]@{
                    Name = $module.Name
                    Version = $module.Version
                    Source = 'PSGallery'
                    Id = $module.Name
                }
            }
        }
        catch {
            # Ignore errors
        }
    }
}

function Install-SelectedPackage {
    [CmdletBinding()]
    param($Package)

    Clear-Host
    Write-Host "Installing $($Package.Name) from $($Package.Source)..." -ForegroundColor Yellow
    Write-Host ""

    try {
        if ($Package.Source -eq 'winget') {
            winget install $Package.Id --accept-source-agreements --accept-package-agreements
        } else {
            Install-Module -Name $Package.Name -Scope CurrentUser -Force
        }
        Write-Host ""
        Write-Host "Installation complete!" -ForegroundColor Green
    }
    catch {
        Write-Host ""
        Write-Host "Installation failed: $_" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "Press any key to continue..." -ForegroundColor DarkGray
    [Console]::ReadKey($true) | Out-Null

    Refresh-CurrentTab
}

function Update-SelectedPackage {
    [CmdletBinding()]
    param($Package)

    Clear-Host
    Write-Host "Updating $($Package.Name) from $($Package.Source)..." -ForegroundColor Yellow
    Write-Host ""

    try {
        if ($Package.Source -eq 'winget') {
            winget upgrade $Package.Id --accept-source-agreements --accept-package-agreements
        } else {
            Update-Module -Name $Package.Name -Force
        }
        Write-Host ""
        Write-Host "Update complete!" -ForegroundColor Green
    }
    catch {
        Write-Host ""
        Write-Host "Update failed: $_" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "Press any key to continue..." -ForegroundColor DarkGray
    [Console]::ReadKey($true) | Out-Null

    Refresh-CurrentTab
}

function Uninstall-SelectedPackage {
    [CmdletBinding()]
    param($Package)

    Clear-Host
    Write-Host "Uninstalling $($Package.Name) from $($Package.Source)..." -ForegroundColor Yellow
    Write-Host "Are you sure? (Y/N): " -NoNewline -ForegroundColor Red

    $confirm = [Console]::ReadKey($true)
    if ($confirm.Key -ne 'Y') {
        return
    }

    Write-Host ""
    Write-Host ""

    try {
        if ($Package.Source -eq 'winget') {
            winget uninstall $Package.Id
        } else {
            Uninstall-Module -Name $Package.Name -Force
        }
        Write-Host ""
        Write-Host "Uninstallation complete!" -ForegroundColor Green
    }
    catch {
        Write-Host ""
        Write-Host "Uninstallation failed: $_" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "Press any key to continue..." -ForegroundColor DarkGray
    [Console]::ReadKey($true) | Out-Null

    Refresh-CurrentTab
}

#endregion

# Export the main function
Export-ModuleMember -Function Start-PackageManagerTUI
