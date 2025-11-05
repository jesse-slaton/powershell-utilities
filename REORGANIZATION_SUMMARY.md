# Script Reorganization Summary

This document summarizes the findings from the script structure analysis and provides quick reference for the reorganization effort.

## Quick Stats

- **Total PowerShell files**: ~180 scripts
- **Current top-level directories**: 13
- **Proposed granular subdirectories**: ~40+
- **Files to rename**: 6
- **Duplicate files**: 1
- **Misplaced modules**: 12
- **Files needing review**: 20+

## Files to Rename

### Immediate Renames (Remove Ticket Numbers/Fix Names)

| Current Path | New Path | Reason |
|-------------|----------|---------|
| `Scripts/Network/CHG0000000_DisableNetBiosOverTCPIP.ps1` | `Scripts/Network/Configuration/Disable-NetBiosOverTCPIP.ps1` | Remove CHG number |
| `Scripts/General/move_win10.ps1` | `Scripts/ActiveDirectory/ComputerManagement/Move-Win10ComputersToOU.ps1` | Non-descriptive name, misplaced |
| `Scripts/General/StuffedScopeArray.ps1` | `Scripts/Network/Monitoring/Get-NetworkLocationByScope.ps1` | Unclear name |
| `Scripts/Utilities/RecieverCleanupUtilityWrapper.ps1` | `Scripts/Utilities/Tools/ReceiverCleanupUtilityWrapper.ps1` | Typo: "Reciever" |
| `Scripts/Security/HylandCompliance-PC-0026-Package.ps1` | _Remove or merge_ | Duplicate with ticket number |

## Files to Remove/Review

### Duplicates
- `Scripts/Network/GetLastComputerPolicyRefresh.ps1` - Remove (keep ActiveDirectory version)

### Client-Specific (May not belong in public repo)
- `Scripts/General/Backup-ChromeBookmarks-Contoso.ps1`
- `Scripts/General/move_win10.ps1` (contains 266 hardcoded hostnames)
- `Scripts/General/Create-PAXInstallShortCut.ps1`

### Development/Test Files (Should be in Tests/)
- `Scripts/General/test-UIforPS7.ps1`
- `Scripts/Development/Test-Threatpulse.ps1`
- `Scripts/Development/Test-AAfDConfigFile.ps1`
- `Scripts/Office/Test-SoapData.ps1`
- `Scripts/Office/Test-Command.ps1`

## Modules Misplaced in Scripts/Network/

These 12 files should be moved to `Modules/`:

1. `AdobeReader.psm1-Package.ps1` - May need conversion to proper module
2. `Certificates.psm1` → `Modules/Certificates/`
3. `Chrome.psm1-Package.ps1` - May need conversion to proper module
4. `Compliance.psm1-Package.ps1` - May need conversion to proper module
5. `Excel.psm1` → `Modules/Office/`
6. `GitHub.psm1` → `Modules/GitHub/`
7. `GroupPolicy.psm1-Package.ps1` - May need conversion to proper module
8. `NetBIOS.psm1` → `Modules/NetBIOS/`
9. `PowerShell.psm1` - Needs review (generic name)
10. `SMB.psm1` → `Modules/SMB/`
11. `STIG.psm1` → `Modules/STIG/`
12. `iadgov.psm1` → `Modules/STIG/` (related to STIG)

**Note**: Files ending in `-Package.ps1` may be Tanium packages that import modules, not actual modules. Needs investigation.

## Major Reorganizations

### Break up "General" Directory (47 files → 0)
Current General directory is a catch-all. Scripts will be distributed to:
- `ServiceNow/` (16 scripts)
- `Utilities/` (15 scripts)
- `Application/Chrome/` (3 scripts)
- `ActiveDirectory/` (1 script)
- `Network/` (1 script)
- `UncategorizedOrDeprecated/` (11 scripts)

### Reorganize Network Directory
Current mix of modules, configuration, monitoring, and Windows customization:
- Modules → `Modules/`
- Windows debloat/customization → `System/WindowsCustomization/`
- Network config → `Network/Configuration/`
- Monitoring → `Network/Monitoring/`

### Split Office Directory
- General → `Office/Configuration/`
- Outlook-specific → `Office/Outlook/`
- Diagnostics → `Office/Diagnostics/`

### Split Security Directory
- BitLocker → `Security/BitLocker/`
- Device Guard → `Security/DeviceGuard/`
- Compliance → `Security/Compliance/`

### Reorganize FileSystem Directory
- Network profiles → `Network/Profiles/`
- Chrome profiles → `Application/Chrome/`
- File monitoring → `FileSystem/Monitoring/`
- Validation → `FileSystem/Validation/`

## Verification Status

### ✅ Verified: No *arr or Emby scripts
- Searched for: `*arr`, `*emby*`, `*sonarr*`, `*radarr*`, `*lidarr*`
- Only match: `StuffedScopeArray.ps1` (false positive - contains "Array")
- **Action**: None needed

## Import Dependencies to Check

Before moving files, scan for:
- `. ` (dot-sourcing patterns)
- `Import-Module` statements
- Relative path references (`..\`, `.\`)
- Hardcoded path references

## Next Steps

1. Review and approve reorganization plan
2. Create backup/feature branch
3. Scan for import dependencies
4. Implement Phase 1: Cleanup (renames, duplicate removal)
5. Implement Phase 2: Create subdirectories
6. Implement Phase 3: Move files
7. Implement Phase 4: Update dependencies
8. Implement Phase 5: Test and validate

## Related Files

- `.github-issue-reorganize.md` - Full reorganization issue
- `.github-issue-unclear-files.md` - Documentation/review issue
- `docs/MODULE_OPPORTUNITIES.md` - Module consolidation plan

---
Generated: 2025-11-05
Analysis tool: Claude Code
