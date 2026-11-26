# PowerShell coding standard

This file is the coding standard for every PowerShell file in this repository (`.ps1`, `.psm1`,
`.psd1`). It applies to new and changed code. Untouched legacy files are tracked in a baseline
(rule 14) and are brought into line when a PR edits them.

Contents: [Scope](#scope) | [Related standards](#related-standards) | [1 File names](#1-file-names) | [2 Indentation](#2-indentation) | [3 Output streams](#3-output-streams) | [4 Legacy APIs](#4-legacy-apis) | [5 Module management](#5-module-management) | [6 Aliases](#6-aliases-and-positional-parameters) | [7 Errors](#7-errors) | [8 Header](#8-header) | [9 Strict mode](#9-strict-mode) | [10 Braces and whitespace](#10-braces-and-whitespace) | [11 Casing](#11-casing) | [12 Encoding](#12-encoding-and-line-endings) | [13 switch vs if](#13-branching-switch-vs-if) | [14 Enforcement](#14-enforcement)

## Scope

`Tests/**` is exempt from rule 1 (Pester needs `<Name>.Tests.ps1`) and from all of rule 8 (the
header rules, including help, which the
[Comment-based help standard](./README.md#comment-based-help-standard) already exempts). Fixture
files under `Tests/Fixtures/`, and files a test writes, are exempt from every rule except rule 12,
because a fixture may need to break a rule on purpose but must never be UTF-16
(`Tests/Encoding.Tests.ps1` checks every tracked file). The exemptions are implemented in #152.

## Related standards

These are not repeated here:

- Comment-based help: [Comment-based help standard](./README.md#comment-based-help-standard) (#54).
- Module layout and manifests: [Module layout standard](./README.md#module-layout-standard) (#40),
  enforced by `Tests/Modules.Tests.ps1`.

## About the checks

Most checks below do not exist yet. They are planned in #151, which is delivered in four parts:

1. #152: the baseline mechanism, the extended `PSScriptAnalyzerSettings.psd1` (it already exists
   and carries the compatibility rules CI uses), whitespace, brace and indentation rules,
   line endings, `.editorconfig`, `.gitattributes`, and the scope exemptions.
2. #153: streams, aliases, errors and header rules.
3. #154: custom AST rules (an AST rule reads the parsed script, so it can check what the stock
   analyzer cannot): legacy APIs, module management, `switch` vs `if`.
4. #155: file-name, strict-mode and casing checks.

Each rule names the issue that adds its check ("planned, #153") unless a check really runs today.
Until a check lands, the rule is still the standard and reviewers apply it by hand.

## 1. File names

Rule: name each script `Verb-Noun.ps1`. The verb is an approved verb, the noun is a singular
PascalCase noun. `-Sensor` and `-Package` are the only allowed suffixes after the noun. No
spaces, no underscores.

```powershell
Get-InstalledSoftware.ps1           # good
Get-AttachedMonitorInfo-Sensor.ps1  # good: -Sensor suffix
get_installed_softwares.ps1         # bad: underscores, lower case, plural noun
Fetch-Data.ps1                      # bad: Fetch is not an approved verb
```

Rule 1a: approved verbs are required in both places, function names and file names. The file-name
check takes the part before the first hyphen and tests it against `(Get-Verb).Verb`.

Why: `Verb-Noun` names are what PowerShell users expect, they sort and tab-complete predictably, and
they match the function inside. Spaces and underscores break quoting and the naming convention.
Approved verbs are checked twice because PSScriptAnalyzer only inspects function definitions and
never looks at file names.

How it is checked:

- File name (Verb-Noun, approved verb, allowed suffixes only): `Tests/Repository.Tests.ps1`
  (planned, #155).
- Function names: PSScriptAnalyzer `PSUseApprovedVerbs` at Error (planned, #152, which extends
  the existing `PSScriptAnalyzerSettings.psd1`).

## 2. Indentation

Rule: 4 spaces per level, no tabs. A pipeline continuation line is indented one extra level.

```powershell
Get-CimInstance -ClassName Win32_Service |
    Where-Object { $_.State -eq 'Running' } |
    Select-Object -Property Name, StartMode
```

Why: one indentation width keeps diffs small and the code readable in every editor, and tabs render
at different widths. The continuation indent shows which lines belong to one statement.

How it is checked: PSScriptAnalyzer `PSUseConsistentIndentation` with spaces and size 4, which
also flags tab-indented lines (planned, #152). `.editorconfig` sets the same width in editors
(planned, #152).

## 3. Output streams

Rule: `Write-Host` is banned.

- Data goes to the pipeline (implicit output or `Write-Output`).
- Diagnostics go to `Write-Verbose`.
- Problems go to `Write-Warning` or `Write-Error`.
- Long runs report with `Write-Progress`.

```powershell
Write-Host "Found $count disks"                      # bad
Write-Verbose "Found $count disks"                    # good: diagnostics
[pscustomobject]@{ Name = $name; Free = $free }       # good: data
```

Why: `Write-Host` bypasses the pipeline, so callers cannot capture, redirect, filter or test its
output, and a script that prints instead of returning objects cannot be composed with other
commands. Separate streams let the caller choose what to see.

How it is checked: PSScriptAnalyzer `PSAvoidUsingWriteHost` at Error (planned, #153).

## 4. Legacy APIs

Rule: these are banned. Each check message names the replacement.

| Banned | Use instead |
| --- | --- |
| `Get-WmiObject`, `Remove-WmiObject`, `Set-WmiInstance`, `Invoke-WmiMethod`, `Register-WmiEvent`, `[wmi]`, `[wmiclass]`, `[wmisearcher]` | `Get-CimInstance`, `Set-CimInstance`, `New-CimInstance` (`Set-WmiInstance` creating an instance), `Remove-CimInstance`, `Invoke-CimMethod`, `Register-CimIndicationEvent` (for `Register-WmiEvent`) |
| `Net.WebClient`, `HttpWebRequest` | `Invoke-RestMethod`, `Invoke-WebRequest` |
| `New-Object PSObject` followed by `Add-Member` | `[pscustomobject]@{ ... }` |
| `wmic`, `reg.exe`, `net.exe` where a cmdlet exists | the matching cmdlet (`Get-CimInstance`, `Get-ItemProperty`, `Get-SmbShare`, and so on) |
| `Invoke-Expression` | a direct call, `&`, or a parameter; allowed only with a justified suppression (below) |
| `[Reflection.Assembly]::LoadWithPartialName` | `Add-Type -AssemblyName` |

```powershell
# bad
$os = Get-WmiObject -Class Win32_OperatingSystem
# good
$os = Get-CimInstance -ClassName Win32_OperatingSystem
```

Suppressing `Invoke-Expression` takes a `SuppressMessage` attribute with a written justification.
Use this exact form (the attribute goes on the function or script `param` block):

```powershell
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '',
    Justification = 'The command text comes from the signed vendor manifest, not from user input.')]
```

An empty or missing `Justification` is still a violation. The stock `PSAvoidUsingInvokeExpression`
at Error flags the call, but it accepts a suppression with no `Justification`, so the custom rule
in #154 also enforces a non-empty one.

Why: the WMI cmdlets are Windows PowerShell only and are removed in PowerShell 7; CIM works in
both. `WebClient` and `HttpWebRequest` are superseded and need far more code than the web
cmdlets. `Add-Member` on a bare object is slow and verbose next to a `[pscustomobject]` literal.
The old command-line tools return text that must be parsed, where cmdlets return objects.
`Invoke-Expression` runs a string as code, which is a code-injection risk. `LoadWithPartialName`
loads whichever assembly version it finds first.

How it is checked:

- Custom AST rule that names the replacement (planned, #154).
- `Invoke-Expression`: PSScriptAnalyzer `PSAvoidUsingInvokeExpression` at Error (planned, #154),
  plus the custom #154 rule that rejects a suppression with an empty or missing `Justification`.

## 5. Module management

Rule: install and update modules with PSResourceGet (`Install-PSResource`, `Find-PSResource`,
`Update-PSResource`, `Get-InstalledPSResource`).

- PSResourceGet ships with PowerShell 7.4 and later. On PowerShell 7.0 to 7.3 it is a host
  prerequisite: install the `Microsoft.PowerShell.PSResourceGet` module once, by hand, before
  running the script. A script does not bootstrap it; when `Install-PSResource` is missing on
  PowerShell 7 it stops with an error that names the module, as
  `Tests/Install-TestDependencies.ps1` does.

- PowerShellGet v2 (`Install-Module`, `Find-Module`, `Update-Module`) is allowed only inside a
  guarded fallback branch: `if ($PSVersionTable.PSEdition -eq 'Desktop') { ... }`.
- After #145 drops Windows PowerShell 5.1, PowerShellGet v2 is banned outright and the guard
  exception goes away. The check is updated when #145 lands.
- Bootstraps that install the NuGet package provider (`Install-PackageProvider NuGet`) or register
  the gallery (`Register-PSRepository PSGallery`) are banned now.
- Forcing TLS 1.2 is allowed for the current process only, and only on the 5.1 fallback branch.

```powershell
if ($PSVersionTable.PSEdition -eq 'Desktop') {
    # 5.1 fallback, removed when #145 lands
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Install-Module -Name Pester -Scope CurrentUser
} else {
    if (-not (Get-Command -Name Install-PSResource -ErrorAction Ignore)) {  # absent on 7.0-7.3
        throw 'Install the Microsoft.PowerShell.PSResourceGet module first (it ships with PowerShell 7.4+).'
    }
    Install-PSResource -Name Pester -Scope CurrentUser
}
```

Why: PSResourceGet is the maintained successor to PowerShellGet v2 and ships with current
PowerShell. The v2 bootstraps change machine-wide package and repository state, and a global TLS
change affects every other script in the session.

How it is checked: custom AST rule flagging a PowerShellGet v2 call outside a `PSEdition -eq
'Desktop'` guard, the NuGet and `Register-PSRepository` bootstraps, and a
`[Net.ServicePointManager]::SecurityProtocol` assignment outside the `Desktop` fallback branch
(planned, #154).

## 6. Aliases and positional parameters

Rule: no aliases in committed code. Write `Where-Object`, not `?` or `where`; `ForEach-Object`, not
`%`; `Get-ChildItem`, not `ls` or `dir`. A positional parameter is allowed only for the obvious first
parameter; name every other one (at most one positional argument per command).

```powershell
gci C:\Temp | ? { $_.Length -gt 1MB }                          # bad
Get-ChildItem -Path C:\Temp | Where-Object { $_.Length -gt 1MB }  # good
Get-Content $path                                              # good: obvious first parameter
Copy-Item $source $destination                                 # bad: name -Destination
```

Why: aliases differ between platforms and can be redefined, so a script may behave differently from
one machine to the next. Full names are searchable and self-describing. `Invoke-ScriptAnalyzer -Fix
-IncludeRule PSAvoidUsingCmdletAliases` expands aliases for you.

How it is checked:

- PSScriptAnalyzer `PSAvoidUsingCmdletAliases` at Error (planned, #153).
- PSScriptAnalyzer `PSAvoidUsingPositionalParameters` at Error (planned, #153). It fires only at 3
  or more positional arguments, so it does not catch `Copy-Item $source $destination`.
- Custom check: at most one positional argument per command (planned, #153).

## 7. Errors

Rules:

- Where a failure matters, use `-ErrorAction Stop` inside `try`/`catch`.
- A failure on one item writes `Write-Error -ErrorAction Continue` and the loop continues. A
  failure of the whole run throws. The explicit `-ErrorAction Continue` matters: a caller that sets
  `$ErrorActionPreference = 'Stop'` would otherwise turn that `Write-Error` into a terminating
  error and end the loop at the first bad item.
- No empty `catch` blocks.
- Setting `SilentlyContinue` or `Ignore` by any route needs an explanatory comment on the same
  line or the line directly above: `-ErrorAction`, `-WarningAction`, `-InformationAction` and
  `-ProgressAction`, written in full, by their aliases (`-ea`, `-wa`, `-infa`, `-proga`) or by an
  unambiguous prefix (`-ErrorA`); numeric values (`-ea 0`); a splatted hashtable that sets one;
  `$PSDefaultParameterValues`; and assignments to `$ErrorActionPreference` and the other
  preference variables.
- Sensor and package scripts (`*-Sensor.ps1`, `*-Package.ps1`) end with an explicit top-level
  `exit` code.

```powershell
foreach ($itemPath in $Path) {
    try {
        $item = Get-Item -Path $itemPath -ErrorAction Stop
    } catch {
        Write-Error -ErrorAction Continue "Cannot read '$itemPath': $($_.Exception.Message)"
        continue
    }
    $item
}

# The key is absent on clean installs, which is not an error.
$value = Get-ItemProperty -Path $key -Name Version -ErrorAction SilentlyContinue
$value = Get-ItemProperty -Path $key -Name Version -ErrorAction Ignore  # absent on clean installs
```

Why: PowerShell's default is to print a non-terminating error and keep going, so without
`-ErrorAction Stop` a `catch` never runs. An empty `catch` or a bare `SilentlyContinue` hides the
failure, so the next reader cannot tell whether it was intended. Sensor and package runners read the
exit code to decide success.

How it is checked:

- `PSAvoidUsingEmptyCatchBlock` at Error (planned, #153).
- Custom AST rule for `SilentlyContinue`/`Ignore` without a comment, covering every route listed
  above (planned, #153).
- Custom AST rule for a missing top-level `exit` in `*-Sensor.ps1` and `*-Package.ps1` (planned,
  #153).

## 8. Header

Rule: every script starts with:

- Comment-based help graded Complete (see the
  [Comment-based help standard](./README.md#comment-based-help-standard), #54).
- `#Requires -Version 5.1` (add `-Modules` or `-RunAsAdministrator` as needed).
- A blank line between the help block and any comment or `#Requires` line above it. Without the
  blank line, `Get-Help` and `Analyze-HelpCoverage.ps1` do not find the help block.
- `[CmdletBinding()]` and a `param()` block, even when there are no parameters.
- `SupportsShouldProcess` on anything that changes state, with `-WhatIf` and `-Confirm` honored
  through `$PSCmdlet.ShouldProcess`.

```powershell
#Requires -Version 5.1

<#
.SYNOPSIS
...
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$Name
)
```

Why: `[CmdletBinding()]` gives the script the common parameters (`-Verbose`, `-ErrorAction`) that
rules 3 and 7 rely on. `SupportsShouldProcess` lets a user preview a change with `-WhatIf` before it
happens. `#Requires` fails fast with a clear message on an unsupported host instead of failing
halfway.

How it is checked:

- `[CmdletBinding()]`, `param()` and `#Requires -Version 5.1`: `Tests/Repository.Tests.ps1` AST test
  (planned, #153).
- `SupportsShouldProcess` on functions: PSScriptAnalyzer
  `PSUseShouldProcessForStateChangingFunctions` at Error (planned, #153). The stock rule checks
  functions only, not scripts.
- `SupportsShouldProcess` on scripts: custom check that a script whose top level calls a
  state-changing cmdlet declares `[CmdletBinding(SupportsShouldProcess)]` (planned, #153).
- Help grade: `Analyze-HelpCoverage.ps1` grades every file today; a failing check is tracked in #156
  (CI fails below Complete, behind the #152 baseline).

## 9. Strict mode

Rule: call `Set-StrictMode -Version 3.0` at the top level of every module `.psm1` and every new or
ported script. Pin `3.0`; do not use `-Version Latest`. Existing scripts adopt it when a PR edits
them.

Why: strict mode turns use of an unset variable and reads of a missing property into errors, which
catches typos that would otherwise return `$null`. `Latest` changes meaning with each PowerShell
release, so a new release could break a script that did not change.

How it is checked: `Tests/Repository.Tests.ps1` AST test for a top-level
`Set-StrictMode -Version 3.0` (planned, #155).

## 10. Braces and whitespace

Rule: one true brace style (OTBS): the opening brace stays on the line of the statement, and
`else`, `elseif`, `catch` and `finally` go on the line of the closing brace. Put spaces around
operators and after commas. No trailing whitespace. At most one blank line in a row.

```powershell
if ($ready) {
    Start-Work
} else {
    Write-Warning 'Not ready.'
}
$list = @(1, 2, 3)
$sum = $a + $b
```

Why: one layout keeps diffs about behavior instead of formatting, and trailing whitespace and
runs of blank lines are pure noise.

How it is checked:

- PSScriptAnalyzer `PSPlaceOpenBrace`, `PSPlaceCloseBrace` and `PSUseConsistentWhitespace` at
  Error (planned, #152).
- PSScriptAnalyzer `PSAvoidTrailingWhitespace` at Error, for trailing whitespace (planned, #152).
- Custom check for more than one blank line in a row (planned, #152).
- `.editorconfig` mirrors the whitespace rules (planned, #152).

## 11. Casing

Rule:

- PascalCase: functions, parameters, script-scope and module-scope variables, public properties.
- camelCase: local variables.
- Lower-case keywords (`if`, `foreach`, `function`, `param`).
- Canonical casing for cmdlet names (`Get-ChildItem`, not `get-childitem`).

Variable names are case-insensitive in PowerShell, so `$Path` and `$path` are the same variable.
camelCase versus PascalCase is a reading aid, never a way to make two variables. A local must not
reuse a parameter's name in another case.

```powershell
function Get-DiskReport {
    param([string]$ComputerName)
    $diskCount = 0
    foreach ($disk in Get-CimInstance -ClassName Win32_LogicalDisk) { $diskCount++ }
}
```

Why: the casing tells the reader a variable's scope at a glance, and it matches how the built-in
cmdlets and .NET types are written.

How it is checked: PSScriptAnalyzer `PSUseCorrectCasing` at Error, plus a custom AST rule for
keyword case, PascalCase parameters, camelCase locals, and a local that reuses a parameter's name
in another case (planned, #155).

## 12. Encoding and line endings

Rule:

- ASCII preferred. If a file needs any non-ASCII character, save it as UTF-8 with BOM. Never
  UTF-16.
- LF line endings in the repository, set by `.gitattributes` (`*.ps1`, `*.psm1` and `*.psd1` use
  `text eol=lf`).
- Every file ends with a final newline.
- `.editorconfig` mirrors the whitespace rules so editors match.

Why: Windows PowerShell 5.1 reads a BOM-less file with the system code page and garbles non-ASCII
text, so the BOM is required there. Byte-based secret scanners cannot read UTF-16. A fixed line
ending and a final newline keep diffs clean across Windows and Unix.

How it is checked:

- Valid UTF-8, no UTF-16, BOM when non-ASCII: `Tests/Encoding.Tests.ps1` runs today (#108, #126).
- LF line endings and final newline: an end-of-line test in `Tests/Repository.Tests.ps1` (planned,
  #152).
- `.gitattributes` and `.editorconfig` entries (planned, #152).

## 13. Branching (switch vs if)

Rule: an `if`/`elseif` chain that compares ONE variable to 3 or more constants with `-eq` must be a
`switch`. Every `switch` has a `default` clause: a fallback value, `Write-Error`, or `throw`, so an
unexpected value is never silently ignored. `if` stays the norm for boolean conditions, ranges, and
one or two branches.

```powershell
# bad: one variable, three constants
if ($mode -eq 'Fast') { ... } elseif ($mode -eq 'Safe') { ... } elseif ($mode -eq 'Full') { ... }

# good
switch ($mode) {
    'Fast'  { ... }
    'Safe'  { ... }
    'Full'  { ... }
    default { throw "Unknown mode '$mode'." }
}
```

Because `switch` runs every matching case unless one ends with `break`, and walks an array one
element at a time:

- In a `switch` whose cases can overlap (`-Regex`, `-Wildcard`, or a script-block condition such as
  `{ $_ -gt 5 }`), every non-default case ends with `break` or `continue`. A switch of distinct
  constants needs neither.
- Use `continue` when the input can be a collection. `continue` moves to the next element; `break`
  stops the whole switch and skips the remaining elements.
- Duplicate constant labels are an error.
- To run several matching cases on purpose, put a `# switch-fallthrough: <reason>` comment on the
  case's line or the line directly above it. The reason must not be empty.

```powershell
switch -Wildcard ($fileName) {
    # switch-fallthrough: a .ps1 file is counted as a script and as PowerShell
    '*.ps1' { $scripts++ }
    '*.ps*' { $powerShell++; continue }
    default { $other++ }
}
```

Why: a `switch` states "one value, many cases" directly, and the required `default` stops a new or
mistyped value from falling through without any effect. The `break`/`continue` rules exist because
overlapping cases otherwise run together, which is rarely intended.

How it is checked: custom AST rules for an `if` chain of 3 or more `-eq` tests on one variable, a
`switch` with no `default`, a missing `break` or `continue` in an overlapping switch (unless the
non-empty `# switch-fallthrough:` comment is present), and duplicate constant labels (planned,
#154).

## 14. Enforcement

Every rule above is an error for new and changed code. Violations that already exist are recorded in
a checked-in baseline with one entry per file and per rule (planned: `Tests/StandardsBaseline.psd1`,
#152).

- CI fails on a violation that is not in the baseline.
- CI also fails when a baselined violation has been fixed but its entry is still listed. So the
  baseline only ever shrinks.
- A PR that edits a file makes that file compliant: fix every violation in it and delete its
  baseline entries in the same PR.

Why: a baseline lets the standard go live without a repo-wide rewrite, and the shrink-only check
keeps the old debt from growing or being forgotten.

How it is checked: the CI analyzer step moves from informational (#128) to failing, using the
extended `PSScriptAnalyzerSettings.psd1` and the baseline (planned, #152). It must fail on both
Windows PowerShell 5.1 and PowerShell 7.

## Existing checks

These already run and enforce part of this standard:

- `Tests/Encoding.Tests.ps1`: tracked `.ps1`, `.psm1` and `.psd1` files are valid UTF-8, never
  UTF-16 (rule 12).
- `Tests/Repository.Tests.ps1`: no script loads a dependency from a working-directory-relative
  path (a related load-safety rule, #120, not one of the 14 numbered rules).
- `Tests/Modules.Tests.ps1`: the module layout standard (#40).
- `Analyze-HelpCoverage.ps1`: grades comment-based help (rule 8, #54).
