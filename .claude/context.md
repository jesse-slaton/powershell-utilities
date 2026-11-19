# Claude Context for powershell-utilities

## Repository Purpose
General-purpose PowerShell utilities for system administration (not Tanium-specific).

## Current State
- **Status**: Cleanup in progress (help, tests, CI, modules, WMI-to-CIM)
- **Created**: 2025-10-14 from monolithic script collection reorganization
- The old `refactoring` branch is fully merged into `main`; work happens on feature branches off `main`

## Repository Structure
```
powershell-utilities/
  Scripts/       # Scripts grouped by category
  Modules/       # PowerShell modules
  Tests/         # Pester tests
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

## Active Issues
Tracking issues, each with one-PR sub-issues (milestones M1-M5):
1. #1: Replace generated Pester stubs with real tests and CI
2. #2: Consolidate related scripts into PowerShell modules
3. #3: Modernize legacy Windows API usage (VBScript removal done; WMI to CIM remaining)
4. #4: Add comment-based help to every script and module function
5. #71: Remove organization-specific names and personal paths from the public tree

---
Last Updated: 2026-11-19
