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
  Modules/       # PowerShell modules, one folder per module (see "Modules" below)
  Tests/         # Pester tests
```

## Modules

| Module | Exports | Replaces |
| --- | --- | --- |
| `MsiTools` | `Format-MsiLog` (alias `Colorize-MsiLog`), `Get-MsiFileInfo` (alias `Get-MSIProperties`) | `Modules/MyMsiLogColorizer.psm1`, `Scripts/FileSystem/Get-MSIFileInfo.ps1` |

Modules are not published to any gallery. Install by path: import the manifest from a clone,

```powershell
Import-Module ./Modules/MsiTools/MsiTools.psd1
Get-Content C:\Temp\install.log | Format-MsiLog
```

or copy the module folder into a folder on `$env:PSModulePath` and run `Import-Module MsiTools`.
Publishing to the PowerShell Gallery, if wanted, gets its own issue.

### Module layout standard

Every module follows this layout; `Tests/Modules.Tests.ps1` enforces it.

```
Modules/
  <Name>/
    <Name>.psd1        # manifest
    <Name>.psm1        # loader: dot-sources Private/*.ps1 then Public/*.ps1, exports Public
    Public/<Verb-Noun>.ps1   # one exported function per file, file named after the function
    Private/*.ps1      # internal helpers, never exported
Tests/Unit/<Name>.Tests.ps1  # behavior tests for the module
```

- `Modules/` holds only module folders. Scripts live under `Scripts/<Category>/`.
- Use approved verbs. When a function is renamed, keep the old name as an `[Alias()]` on the
  function and list it in `AliasesToExport`.
- Comment-based help goes inside each function body and meets the standard below.

Manifest rules:

| Key | Rule |
| --- | --- |
| `RootModule` | `<Name>.psm1` |
| `FunctionsToExport` | Explicit list, no wildcard; exactly the `Public/*.ps1` file names |
| `AliasesToExport`, `CmdletsToExport`, `VariablesToExport` | Explicit lists, `@()` when empty |
| `PowerShellVersion` | `'5.1'` |
| `CompatiblePSEditions` | `@('Desktop', 'Core')` |
| `RequiredModules` | Declared, `@()` when there are none |

Module behavior tests live in `Tests/Unit/` with the script tests rather than inside the module
folder: CI runs `./Tests` on Windows PowerShell 5.1 and PowerShell 7, the shared harness is there,
and the orphaned-test check covers them. A test imports the manifest (importing only defines
functions) and mocks with `-ModuleName <Name>`; wrap COM, registry, network and other
machine-touching calls in a `Private/` helper so they can be mocked on any OS.

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
3. Add comment-based help that meets the standard below
4. Run PSScriptAnalyzer before committing
5. Create feature branches for changes
6. Save PowerShell files (`.ps1`, `.psm1`, `.psd1`) as UTF-8, with a BOM when a file holds
   non-ASCII text that Windows PowerShell 5.1 must read. Never UTF-16: secret scanners cannot
   read it. `Tests/Encoding.Tests.ps1` fails on a tracked UTF-16 file, and the Gitleaks workflow
   scans the new commits of each pull request and of each push to `main` for credentials.

### Comment-based help standard

Every `.ps1` under `Scripts/` and `Modules/`, and every exported function in a `.psm1`, has a
comment-based help block with:

| Keyword | Requirement |
| --- | --- |
| `.SYNOPSIS` | One line saying what it does |
| `.DESCRIPTION` | What it reads or changes, and its output |
| `.PARAMETER` | One per declared parameter |
| `.EXAMPLE` | At least one; at least two when it takes parameters |
| `.NOTES` | Prerequisites: admin rights, a vendor agent (Tanium, Altiris, ...), required modules, PowerShell edition. Write `None` if there are none |

Rules:

- Place the block at the top of a script (before `param()`), or as the first thing inside a
  function body.
- Test files (`Tests/**`) are exempt.
- Help is read in the shell with `Get-Help <path-or-function> -Full`. There are no separate
  per-script Markdown pages; if a rendered site is wanted later, generate it with platyPS.
- `Analyze-HelpCoverage.ps1` grades every file against this standard (Complete, Partial or None)
  without running any script. Run it locally before opening a PR.

## Documentation

- [EXTERNAL_REPOS.txt](./EXTERNAL_REPOS.txt) - Upstream sources for archived and vendored scripts
- [ARCHIVED.md](./ARCHIVED.md) - First-party scripts removed from main, and where to find them in git history
- Comment-based help in each script: `Get-Help <path-to-script> -Full` (see the standard above)

---

Initial import: 2025-10-14 (tag `v0.1-baseline`)

