# Create More Granular Subdirectory Structure

## Description
The current Scripts directory structure uses 11 top-level categories, but many categories contain a large number of scripts (e.g., General: 47 scripts, Network: 48 scripts) that could benefit from more granular organization.

## Current Structure
```
Scripts/
├── ActiveDirectory/     (13 scripts)
├── Application/         (5 scripts)
├── Backup/             (5 scripts)
├── Development/        (2 scripts)
├── FileSystem/         (16 scripts)
├── General/            (47 scripts) ⚠️ Too broad
├── Network/            (48 scripts) ⚠️ Too broad
├── Office/             (14 scripts)
├── Security/           (11 scripts)
├── System/             (24 scripts)
└── Utilities/          (3 scripts)
```

## Proposed Subdirectory Improvements

### General/ → Break into:
- `General/ServiceNow/` - ServiceNow API integration scripts (12+ scripts)
- `General/SystemInfo/` - System information gathering
- `General/Shortcuts/` - Shortcut creation scripts
- `General/WindowsIndex/` - Windows Search index scripts
- `General/Diagnostics/` - Diagnostic and testing scripts
- `General/Misc/` - Remaining miscellaneous utilities

### Network/ → Break into:
- `Network/DNS/` - DNS-related scripts
- `Network/WMI/` - WMI monitoring and queries
- `Network/VPN/` - VPN configuration scripts
- `Network/Monitoring/` - Network monitoring sensors
- `Network/Configuration/` - Network adapter configuration
- `Network/Compliance/` - Network compliance checks

### Office/ → Consider:
- `Office/C2R/` - Click-to-Run management
- `Office/365/` - Office 365 specific scripts
- `Office/LanguagePacks/` - Language pack management

### System/ → Break into:
- `System/Updates/` - Windows Update scripts
- `System/Cleanup/` - Cleanup and removal scripts
- `System/Configuration/` - System configuration scripts
- `System/MicroStrategy/` - MicroStrategy-specific scripts

### FileSystem/ → Consider:
- `FileSystem/Profiles/` - Profile management (VPN, 802.1x)
- `FileSystem/DriveHealth/` - Drive health monitoring
- `FileSystem/Backup/` - Backup-related file operations

## Import Dependencies to Review

Before moving scripts, audit for:
1. **Dot-sourcing**: Scripts that load other scripts via `. .\OtherScript.ps1`
2. **Module imports**: References to relative paths in `Import-Module`
3. **Hard-coded paths**: Scripts referencing other scripts by path
4. **Shared configuration files**: Multiple scripts reading same config

### Known Dependencies:
- ServiceNow scripts may share common functions (check ServiceNow.psm1 module)
- Package scripts may have dependencies on other scripts
- Sensor scripts often reference utility functions

## Implementation Checklist

- [ ] Create dependency map of all scripts
- [ ] Identify scripts that import/reference other scripts
- [ ] Create new subdirectory structure
- [ ] Move scripts to new locations
- [ ] Update all import paths and references
- [ ] Update test file paths in Tests/Unit/
- [ ] Update documentation paths in docs/
- [ ] Update README.md with new structure
- [ ] Run all tests to verify nothing broke

## Notes

- Use `Grep` to search for patterns like:
  - `. .\` or `. "$PSScriptRoot` (dot-sourcing)
  - `Import-Module` with relative paths
  - `Invoke-Expression` with script paths
- Consider keeping frequently-used utility scripts in a `Common/` or `Lib/` folder
- May want to create an index/manifest file to help locate scripts after reorganization
