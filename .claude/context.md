# Claude Context for powershell-utilities

## Repository Purpose
General-purpose PowerShell utilities for system administration (not Tanium-specific).

## Current State
- **Status**: Initial import complete, refactoring in progress
- **Created**: 2025-10-14 from monolithic script collection reorganization

## Repository Structure
```
powershell-utilities/
  Scripts/       # General utility scripts
  Modules/       # PowerShell modules
  Tests/         # Pester tests
  docs/          # Documentation
```

## Owner Requirements
The repository owner requires assistance with:

1. **Headers/Comments**: Complete, consistent comment-based help for all scripts
2. **Parameters**: Standardized common parameters across similar scripts (e.g., -Force, -WhatIf)
3. **Pester Tests**: Test coverage for all functionality
4. **Documentation**: General usage documentation and patterns

## Development Workflow
1. Write tests for all new scripts
2. Add comment-based help to all functions
3. Run PSScriptAnalyzer before committing
4. Use feature branches for changes

## Git Commit Preferences
- **NEVER** include co-authored attributions (no "Co-Authored-By: Claude" lines)
- Keep commit messages concise and descriptive
- Reference issue numbers when applicable

## Related Repository
- **tanium-powershell**: Tanium-specific sensors and packages (see `.claude/context.md` there)

## Current Work (As of 2025-10-15)
- **Issue 5**: Create TUI similar to UniGetUI - COMPLETED
  - [x] Discover tab: Search and install packages
  - [x] Updates tab: View and apply available updates
  - [x] Installed tab: Manage installed packages
  - [x] Settings tab: Configure sources and options
  - [x] Keyboard navigation and controls
  - [x] Support for winget and PowerShell Gallery
  - [ ] Bulk operations (future enhancement)
  - [ ] Elevation support (future enhancement)

## Active Issues
1. Issue #1: Write Pester tests for all scripts
2. Issue #2: Identify and consolidate scripts into PowerShell modules
3. Issue #3: Remove VBScript dependencies and modernize scripts
4. Issue #4: Add comment-based help to all scripts
5. Issue #5: Create a TUI in the same fashion as UniGetUI

---
Last Updated: 2025-10-15
