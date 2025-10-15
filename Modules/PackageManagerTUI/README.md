# PackageManagerTUI

Terminal User Interface for managing Windows packages and PowerShell modules.

## Overview

PackageManagerTUI provides a text-based interactive interface for discovering, installing, updating, and removing packages from multiple sources (winget and PowerShell Gallery). Inspired by UniGetUI but designed for terminal use.

## Features

- **Discover Packages**: Search and install packages from winget and PowerShell Gallery
- **Software Updates**: View and apply available updates for installed packages
- **Installed Packages**: Manage installed packages (view and uninstall)
- **Settings**: Configure package sources and display options
- **Keyboard Navigation**: Full keyboard-driven interface
- **Multi-Source**: Supports both winget and PowerShell Gallery

## Requirements

- PowerShell 5.1 or higher
- winget (Windows Package Manager) - optional but recommended
- Internet connection for package discovery

## Installation

### Quick Start

From the repository root:

```powershell
.\Start-PackageManagerTUI.ps1
```

### Import as Module

```powershell
Import-Module .\Modules\PackageManagerTUI\PackageManagerTUI.psd1
Start-PackageManagerTUI
```

## Usage

### Keyboard Controls

| Key | Action |
|-----|--------|
| Tab / ← → | Switch between tabs |
| ↑ ↓ | Navigate package list |
| Enter | Execute action on selected package |
| Ctrl+F | Search for packages (Discover tab) |
| Ctrl+R | Refresh current tab |
| Q / Esc | Quit application |

### Tabs

#### 1. Discover Packages

Search and install packages from configured sources.

1. Press `Ctrl+F` to start a search
2. Enter search terms
3. Use arrow keys to select a package
4. Press `Enter` to install

#### 2. Software Updates

View and install available updates for installed packages.

1. Navigate to Updates tab
2. Select a package with updates available
3. Press `Enter` to update

#### 3. Installed Packages

Manage currently installed packages.

1. Browse installed packages
2. Select a package
3. Press `Enter` to uninstall (confirmation required)

#### 4. Settings

Configure package sources and display options.

- Enable/disable winget and PSGallery sources
- Adjust page size for package lists
- Configure auto-refresh behavior

## Configuration

Settings are automatically saved to:
```
%USERPROFILE%\.packagemanagertui\settings.json
```

### Default Settings

```json
{
    "EnabledSources": ["winget", "PSGallery"],
    "AutoRefresh": true,
    "PageSize": 15
}
```

## Examples

### Basic Usage

```powershell
# Launch the TUI
Start-PackageManagerTUI

# Search for a package
# 1. Press Ctrl+F
# 2. Type: "git"
# 3. Select Git.Git from results
# 4. Press Enter to install
```

### Install PowerShell Module

```powershell
# In Discover tab:
# 1. Press Ctrl+F
# 2. Search: "Pester"
# 3. Select from PSGallery results
# 4. Press Enter to install
```

### Update All Packages

```powershell
# In Updates tab:
# Navigate through the list and press Enter on each package to update
```

## Package Sources

### winget (Windows Package Manager)

Manages applications installed through the Windows Package Manager.

- Requires winget to be installed
- Access to thousands of Windows applications
- Handles system-level installations

### PowerShell Gallery

Manages PowerShell modules from the PowerShell Gallery.

- No additional requirements
- Access to PowerShell modules and scripts
- Installs to current user scope

## Troubleshooting

### "winget is not installed"

Install winget from the Microsoft Store or download the App Installer package:
https://learn.microsoft.com/en-us/windows/package-manager/winget/

### Package operations require elevation

Some winget packages require administrator privileges. Run PowerShell as Administrator.

### PowerShell Gallery packages fail to install

Ensure you have internet connectivity and the PowerShellGet module is up to date:

```powershell
Install-Module PowerShellGet -Force
```

## Architecture

The module is structured as a single-file module with the following components:

- **Core TUI Functions**: Main loop, initialization, display rendering
- **Tab Display Functions**: Individual tab rendering logic
- **Action Functions**: User interaction handlers
- **Package Operations**: Backend operations for install/update/remove

## Development

### Testing Changes

```powershell
# Reload the module after making changes
Import-Module .\Modules\PackageManagerTUI\PackageManagerTUI.psd1 -Force
Start-PackageManagerTUI
```

### Adding New Package Sources

To add support for additional package managers:

1. Add source name to `$script:Settings.EnabledSources`
2. Implement search logic in `Search-Packages`
3. Implement update detection in `Get-AvailableUpdates`
4. Implement listing in `Get-InstalledPackages`
5. Add install/update/uninstall logic in respective functions

## Known Limitations

- Bulk operations (installing/updating multiple packages at once) not yet implemented
- Settings configuration via UI not yet implemented (manual JSON editing required)
- No package details view (click a package to see description, dependencies, etc.)
- Elevation/runas functionality not implemented

## Future Enhancements

- [ ] Bulk install/update/remove operations
- [ ] Package details view
- [ ] Interactive settings configuration
- [ ] Support for additional sources (Chocolatey, Scoop, npm)
- [ ] Export/import package lists
- [ ] Scheduled update checks
- [ ] Notification system

## Version History

### v1.0.0 (2025-10-15)
- Initial release
- Discover, Updates, and Installed tabs
- winget and PowerShell Gallery support
- Search functionality
- Basic settings support

## License

See repository license file.

## Author

Jesse Slaton

## Related Issues

- Issue #5: Create a TUI in the same fashion as UniGetUI
