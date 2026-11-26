# Tests

Pester 5 suite. Running it never executes a script under test.

## Running

```powershell
. ./Tests/Install-TestDependencies.ps1   # installs and imports pinned Pester 5.6.1 and PSScriptAnalyzer 1.23.0
Invoke-Pester ./Tests
```

The installer uses `Install-PSResource` (PSResourceGet, built into PowerShell 7.4 and later). Windows
PowerShell 5.1 without PSResourceGet falls back to `Install-Module`, and the output names which command
ran. PowerShell 7.0 to 7.3 need the `Microsoft.PowerShell.PSResourceGet` module installed first.

### On macOS or Linux

The suite runs under PowerShell 7 (`pwsh`) off Windows too. From the repository root:

```sh
pwsh -NoProfile -c '. ./Tests/Install-TestDependencies.ps1; Invoke-Pester ./Tests -Output Detailed'
```

Windows-only commands (`Get-CimInstance`, `Get-WinEvent`, the BitLocker and ActiveDirectory
cmdlets) do not exist there, so a behavior test stubs them with `Register-CommandStub` before
mocking them (below). A test that needs real Windows behavior, not a mock, goes in its own `Describe`
with `-Skip:(-not $script:onWindows)`, set in `BeforeDiscovery` as described in the root README.

### Pre-push gate

`.gates.toml` at the repository root defines the local gate for the orchestrate gate-runner:
the whole Pester suite (exits non-zero on any failed test) and `actionlint` over the workflows.
Each step is skipped when `pwsh` or `actionlint` is not on `PATH`.

### Coverage

CI writes JaCoCo line coverage of `Scripts/` and `Modules/` to `coverage.xml` in the
`test-results-*` artifact. To get the same locally:

```powershell
$config = New-PesterConfiguration
$config.Run.Path = './Tests'
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = @('./Scripts', './Modules')
$config.CodeCoverage.OutputFormat = 'JaCoCo'
$config.CodeCoverage.OutputPath = 'coverage.xml'
Invoke-Pester -Configuration $config
```

Functions loaded with `Get-ScriptFunctionDefinition` keep the script's path and line numbers,
so their coverage is reported against the real script.

### Windows PowerShell 5.1 compatibility

`PSScriptAnalyzerSettings.psd1` at the repository root enables `PSUseCompatibleSyntax`,
`PSUseCompatibleCommands` and `PSUseCompatibleTypes` against a Windows PowerShell 5.1 profile and a
PowerShell 7 on Windows profile, so 5.1 problems show up on any OS. CI reports the findings in an
informational step; the comment at the top of the settings file shows the local command.

## Layout

| File | Purpose |
| --- | --- |
| `Smoke.Tests.ps1` | For every tracked `.ps1`/`.psm1` under `Scripts/` and `Modules/`: parses with no syntax errors, and has no PSScriptAnalyzer `Error`-severity findings. The file list comes from `git ls-files`, so new scripts are covered automatically. |
| `Repository.Tests.ps1` | Fails when a `Tests/Unit/<Name>.Tests.ps1` has no matching script or module, or when a file in `Tests/` is missing from this table. |
| `Modules.Tests.ps1` | For every `Modules/<Name>/`: follows the module layout standard in the root README, passes `Test-ModuleManifest`, imports, and exports exactly what its manifest declares. |
| `Encoding.Tests.ps1` | Every tracked `.ps1`, `.psm1` and `.psd1` is valid UTF-8 (never UTF-16), with a BOM when it holds non-ASCII text, and has no stray control characters. Reads bytes only. |
| `Analyze-HelpCoverage.Tests.ps1` | Tests for the root `Analyze-HelpCoverage.ps1` help-coverage report, against fixture scripts written to `$TestDrive` and only parsed. |
| `Install-TestDependencies.ps1` | Installs and imports the pinned Pester and PSScriptAnalyzer versions (see Running). |
| `Install-TestDependencies.Tests.ps1` | Tests for the installer, with the install commands mocked. |
| `TestHelpers.psm1` | Shared helpers: `Resolve-ScriptUnderTest`, `Get-ScriptFunctionDefinition`, `Register-CommandStub`, `Remove-CommandStub`, `Get-TrackedScript`. |
| `TestHelpers.Tests.ps1` | Self-tests for the helpers, including proof that coverage of AST-loaded functions maps to the original file and lines. |
| `Fixtures/` | Sample scripts the self-tests load. Never run them. |
| `Unit/<Name>.Tests.ps1` | Behavior tests for one script or module, named after it (`Unit/MsiTools.Tests.ps1` covers `Modules/MsiTools`). |

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

### Stubbing Windows-only commands

`Mock` needs the command to exist. `Register-CommandStub` defines a global placeholder for each
named command that `Get-Command` cannot find, and leaves real commands alone, so on Windows the
test mocks the real cmdlet. Call it before loading the functions:

```powershell
BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Register-CommandStub -Name Get-CimInstance -Parameter ClassName, Filter, ComputerName
    Register-CommandStub -Name Get-BitLockerVolume -Parameter MountPoint
    . (Get-ScriptFunctionDefinition -Path (Resolve-ScriptUnderTest -Name $PSCommandPath))
}

AfterAll {
    Remove-CommandStub -Name Get-CimInstance, Get-BitLockerVolume
}

It 'reads only network adapters' {
    Mock Get-CimInstance { @() } -ParameterFilter { $ClassName -eq 'Win32_NetworkAdapter' }
    # ...
}
```

- Declare every parameter the code passes by name or that a `-ParameterFilter` reads; Pester
  copies the stub's parameters into the mock. `-Parameter` declares value parameters, bound by
  position in the order given; `-Switch` declares switches. Other arguments are accepted and ignored.
- A stub that runs without a mock throws, so a missing `Mock` fails the test instead of returning nothing.
- Registering the same name again replaces an earlier stub (never a real command) with the new parameters.
- For a command that takes pipeline input, name that parameter: `-Parameter Identity -PipelineParameter Identity`
  lets `'bob' | Remove-ADUser` reach the mock. Common parameter names (`Verbose`, `ErrorAction`, ...) are rejected.
- Stubs are global and outlive the file. Remove them in `AfterAll` with `Remove-CommandStub` (it only ever
  removes stubs), so a later file cannot pass only because this one stubbed a command it forgot to stub.

When two tracked scripts share a name, pass the folder: `Resolve-ScriptUnderTest -Name $PSCommandPath -Category ActiveDirectory`.

If a script keeps its logic in top-level code, the minimal refactor is to move that logic into a
function and call it from the bottom of the script. The test then loads the function as above.

Rules:

- Mock every registry, CIM/WMI, network, service and process call. Confine file effects to `$TestDrive`.
- A test that is not written yet is marked pending with `Set-ItResult -Pending -Because '...'`, never `$true | Should -Be $true`.
- Tests that need a vendor agent or Windows-only COM class go in their own `Describe` with
  `-Skip:(-not $script:onWindows)`, where `$script:onWindows = $env:OS -eq 'Windows_NT'` is set in
  `BeforeDiscovery` (Pester 5 `-Skip` takes no reason; see the root README).
