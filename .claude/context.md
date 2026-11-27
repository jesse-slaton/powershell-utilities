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
Open milestones, each made of one-PR issues (M1-M4 are closed):
- M5: Retire scripts - 12 of 13 done. #134-#144 archived every script MIGRATION.md marked retire,
  and #192 cleaned up the external-repo list. Only #191 remains, blocked on the tanium-powershell
  imports (#52-#54); do not start it until those land.
- M6: Coding standards - enforce STANDARDS.md with PSScriptAnalyzer and AST checks (#151-#156),
  plus #193 (search-hostile characters) and #194 (shared logger).
- M7: Pester behavior tests - real tests for the scripts that remain (#24-#37, #83)
- M8: PowerShell 7 migration - drop the Windows PowerShell 5.1 CI leg (#145)

Open tracking issues: #1 (real tests and CI, finished by M7) and #2 (modules; its module
acceptance criteria are still open). #3 (WMI to CIM) and #4 (comment-based help) are complete.

---
Last Updated: 2026-11-27
