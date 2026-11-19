# Tests

Pester 5 suite. Running it never executes a script under test.

## Running

```powershell
./Tests/Install-TestDependencies.ps1   # pinned Pester 5.6.1 and PSScriptAnalyzer 1.23.0
Invoke-Pester ./Tests
```

## Layout

| File | Purpose |
| --- | --- |
| `Smoke.Tests.ps1` | For every tracked `.ps1`/`.psm1` under `Scripts/` and `Modules/`: parses with no syntax errors, and has no PSScriptAnalyzer `Error`-severity findings. The file list comes from `git ls-files`, so new scripts are covered automatically. |
| `Repository.Tests.ps1` | Fails when a `Tests/Unit/<Name>.Tests.ps1` has no matching script. |
| `TestHelpers.psm1` | Shared helpers: `Resolve-ScriptUnderTest`, `Get-ScriptFunctionDefinition`, `Get-TrackedScript`. |
| `Unit/<Name>.Tests.ps1` | Behavior tests for one script, named after it. |

## Writing a behavior test

Never dot-source or call a script under test directly. Many scripts change machine state at
top level (registry, network adapters, services). Load only its functions from the AST:

```powershell
BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    . (Get-ScriptFunctionDefinition -Path (Resolve-ScriptUnderTest -Name $PSCommandPath))
}

Describe 'Get-Something' {
    It 'returns one object per adapter' {
        Mock Get-CimInstance { @([pscustomobject]@{ Index = 1 }, [pscustomobject]@{ Index = 2 }) }
        (Get-Something).Count | Should -Be 2
    }
}
```

When two tracked scripts share a name, pass the folder: `Resolve-ScriptUnderTest -Name $PSCommandPath -Category ActiveDirectory`.

If a script keeps its logic in top-level code, the minimal refactor is to move that logic into a
function and call it from the bottom of the script. The test then loads the function as above.

Rules:

- Mock every registry, CIM/WMI, network, service and process call. Confine file effects to `$TestDrive`.
- A test that is not written yet is marked pending with `Set-ItResult -Pending -Because '...'`, never `$true | Should -Be $true`.
- Tests that need a vendor agent or Windows-only COM class use `-Skip` with a reason.
