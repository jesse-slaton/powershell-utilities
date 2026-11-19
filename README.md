# powershell-utilities

## Status

**Cleanup in progress**

This repository was created from a reorganization of a monolithic PowerShell script collection.
Scripts are being documented, tested, and consolidated into modules; see the tracking issues
[#4 (help)](https://github.com/jesse-slaton/powershell-utilities/issues/4),
[#1 (tests and CI)](https://github.com/jesse-slaton/powershell-utilities/issues/1),
[#2 (modules)](https://github.com/jesse-slaton/powershell-utilities/issues/2), and
[#3 (legacy API modernization)](https://github.com/jesse-slaton/powershell-utilities/issues/3).

> **Note**: Path Commander (the Windows PATH TUI manager) has been moved to its own repository:
> https://github.com/jesse-slaton/cli-tools

## Purpose

General-purpose PowerShell utilities for system administration

## Current State

- [x] Initial import complete
- [x] VBScript dependencies removed
- [ ] Comment-based help on every script (#4)
- [ ] Real Pester tests and CI (#1)
- [ ] Related scripts consolidated into modules (#2)
- [ ] `Get-WmiObject` replaced with CIM cmdlets (#3)

## Structure

```
powershell-utilities/
  Scripts/       # Scripts grouped by category (ActiveDirectory, Network, System, ...)
  Modules/       # PowerShell modules
  Tests/         # Pester tests
  docs/          # Per-script documentation pages
```


## Prerequisites

### Required PowerShell Modules

```powershell
# Install required modules
Install-Module PSScriptAnalyzer, Pester -Scope CurrentUser -Force

# For specific scripts, you may also need:
# Install-Module ActiveDirectory, AWSPowerShell -Scope CurrentUser
```

### External Repositories

Some scripts depend on external repositories. See `EXTERNAL_REPOS.txt` for:
- Repositories to fork/star
- Installation instructions
- Local path requirements

## Contributing

1. Use approved PowerShell verbs (`Get-Verb`) for new script and function names
2. Write tests for all new scripts
3. Add comment-based help to all functions
4. Run PSScriptAnalyzer before committing
5. Create feature branches for changes

## Documentation

- [EXTERNAL_REPOS.txt](./EXTERNAL_REPOS.txt) - Upstream sources for archived and vendored scripts
- Comment-based help in each script: `Get-Help <path-to-script> -Full`

---

Initial import: 2025-10-14 (tag `v0.1-baseline`)

