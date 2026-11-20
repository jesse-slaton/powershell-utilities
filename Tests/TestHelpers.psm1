#Requires -Version 5.1
<#
.SYNOPSIS
    Shared helpers for the Pester suite. Nothing here runs a script under test.
#>

$script:RepoRoot = Split-Path -Parent $PSScriptRoot

function Get-RepoRoot {
    <#
    .SYNOPSIS
        Returns the repository root folder.
    #>
    $script:RepoRoot
}

function Get-TrackedScript {
    <#
    .SYNOPSIS
        Lists every .ps1 and .psm1 under Scripts/ and Modules/ as FileInfo objects.

    .DESCRIPTION
        Uses `git ls-files` when git is available so untracked scratch files are ignored,
        and falls back to a recursive directory listing otherwise. Test files
        (*.Tests.ps1) are excluded.
    #>
    [CmdletBinding()]
    param()

    $paths = $null
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $paths = & git -C $script:RepoRoot ls-files -- 'Scripts' 'Modules' 2>$null
        if ($LASTEXITCODE -ne 0) { $paths = $null }
    }

    if ($paths) {
        $paths |
            Where-Object { $_ -match '\.psm?1$' -and $_ -notmatch '\.Tests\.ps1$' } |
            ForEach-Object { Get-Item -LiteralPath (Join-Path $script:RepoRoot $_) }
    }
    else {
        Get-ChildItem -Path (Join-Path $script:RepoRoot 'Scripts'), (Join-Path $script:RepoRoot 'Modules') -Recurse -File -Include '*.ps1', '*.psm1' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike '*.Tests.ps1' }
    }
}

function Resolve-ScriptUnderTest {
    <#
    .SYNOPSIS
        Maps a test file or script name to the script it covers under Scripts/<Category>/ or Modules/.

    .PARAMETER Name
        A test file path or name (Foo.Tests.ps1), or a bare script name (Foo).

    .PARAMETER Category
        Folder that holds the script, relative to the repository root, such as
        'Scripts/Network' or 'Modules'. A bare category name such as 'Network' means
        'Scripts/Network'. Use it when more than one tracked script has the same name.

    .EXAMPLE
        $scriptPath = Resolve-ScriptUnderTest -Name $PSCommandPath

    .EXAMPLE
        $scriptPath = Resolve-ScriptUnderTest -Name $PSCommandPath -Category ActiveDirectory
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Category
    )

    $baseName = [System.IO.Path]::GetFileName($Name) -replace '\.Tests\.ps1$', '' -replace '\.psm?1$', ''
    $found = @(Get-TrackedScript | Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $baseName })

    if ($Category) {
        $folder = $Category.Trim('/', '\') -replace '\\', '/'
        if ($folder -notmatch '^(Scripts|Modules)(/|$)') { $folder = "Scripts/$folder" }
        $found = @($found | Where-Object {
                $relative = $_.FullName.Substring($script:RepoRoot.Length + 1) -replace '\\', '/'
                $relative -like "$folder/*"
            })
    }

    $where = if ($Category) { "under '$Category'" } else { 'under Scripts/ or Modules/' }
    if ($found.Count -eq 0) { throw "No script named '$baseName' $where." }
    if ($found.Count -gt 1) { throw "More than one script named '$baseName': $($found.FullName -join ', '). Pass -Category to choose one." }
    $found[0].FullName
}

function Get-ScriptFunctionDefinition {
    <#
    .SYNOPSIS
        Returns a script block that defines a script's top-level functions without running the rest of the script.

    .DESCRIPTION
        Parses the file with the PowerShell AST and keeps only its top-level function
        definitions. Dot-source the result in BeforeAll to test those functions while
        never executing the script's top-level code (which may change registry, network
        adapters, services, or files).

        The returned script block is built from copies of the original AST nodes, so
        every function keeps the script's file path and line numbers. Pester
        CodeCoverage pointed at the script path therefore reports hits on the real
        lines, and error messages and stack traces name the real file.

    .PARAMETER Path
        Path of the .ps1 or .psm1 file.

    .PARAMETER Name
        Only include these function names. Defaults to every top-level function.

    .EXAMPLE
        BeforeAll {
            Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
            . (Get-ScriptFunctionDefinition -Path (Resolve-ScriptUnderTest -Name $PSCommandPath))
        }

    .NOTES
        Dot-source the result (the leading '. '), or the functions are defined in a
        child scope and vanish when it returns.
    #>
    [CmdletBinding()]
    [OutputType([scriptblock])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string[]]$Name
    )

    $Path = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw "Cannot parse '$Path': $($errors[0].Message)" }

    $functions = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false))
    if ($Name) { $functions = @($functions | Where-Object { $Name -contains $_.Name }) }
    if ($functions.Count -eq 0) { throw "No matching top-level functions in '$Path'." }

    # Wrap copies of the function statements in a new script block AST. Copy() keeps each
    # node's extent, so every function it defines reports the original File and line
    # numbers. The wrapper's own extent comes from parsing just the function text (under
    # the same file name), never the whole file, so the result's ToString() holds no
    # top-level code: re-parsing it (Start-Job, [scriptblock]::Create) only defines functions.
    $functionText = ($functions | ForEach-Object { $_.Extent.Text }) -join [Environment]::NewLine
    $wrapperExtent = [System.Management.Automation.Language.Parser]::ParseInput($functionText, $Path, [ref]$tokens, [ref]$errors).Extent
    $statements = New-Object 'System.Collections.Generic.List[System.Management.Automation.Language.StatementAst]'
    foreach ($function in $functions) { $statements.Add($function.Copy()) }
    $traps = New-Object 'System.Collections.Generic.List[System.Management.Automation.Language.TrapStatementAst]'
    $block = New-Object System.Management.Automation.Language.StatementBlockAst -ArgumentList $wrapperExtent, $statements, $traps
    $wrapper = New-Object System.Management.Automation.Language.ScriptBlockAst -ArgumentList $wrapperExtent, $null, $block, $false
    $wrapper.GetScriptBlock()
}

# Text every stub's body contains; it tells a stub from a real command, even after
# this module is re-imported with -Force.
$script:StubMarker = 'is a test stub from Register-CommandStub'

function Register-CommandStub {
    <#
    .SYNOPSIS
        Defines a placeholder for a command that does not exist on this machine, so Pester can Mock it.

    .DESCRIPTION
        Pester's Mock needs the mocked command to exist. Windows-only commands such as
        Get-CimInstance, Get-WinEvent, or the BitLocker and ActiveDirectory cmdlets do
        not exist on macOS or Linux. For each name that Get-Command cannot find, this
        defines a global function with the given parameters. A command that really
        exists is never replaced, so on Windows the test mocks the real command.

        Pester copies the stub's parameters into the mock, so declare every parameter a
        test passes or names in a -ParameterFilter. Parameters bind by position in the
        order given, like most cmdlets bind their first parameter. Any other arguments
        are accepted and ignored.

        The stub throws when it runs, so a call that was not mocked fails loudly instead
        of returning nothing. Calling this again for a command it stubbed earlier
        replaces that stub with the new parameter list.

    .PARAMETER Name
        Command names to stub, such as Get-CimInstance.

    .PARAMETER Parameter
        Value parameters the stub declares, such as ClassName, Filter, ComputerName.

    .PARAMETER Switch
        Switch parameters the stub declares, such as Force or Recurse.

    .PARAMETER PipelineParameter
        One of the -Parameter names that takes pipeline input by value, as Identity
        does for Remove-ADUser. Without it, piped input does not bind
        and the mock is never called.

    .EXAMPLE
        Register-CommandStub -Name Remove-ADUser -Parameter Identity -PipelineParameter Identity

        'bob' | Remove-ADUser then reaches Mock Remove-ADUser with $Identity set to 'bob'.

    .EXAMPLE
        BeforeAll {
            Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
            Register-CommandStub -Name Get-CimInstance -Parameter ClassName, Filter, ComputerName
            . (Get-ScriptFunctionDefinition -Path (Resolve-ScriptUnderTest -Name $PSCommandPath))
        }

        It 'reads the adapters' {
            Mock Get-CimInstance { @() } -ParameterFilter { $ClassName -eq 'Win32_NetworkAdapter' }
        }

    .NOTES
        Stubs are global and outlive the test file, so a later file could pass only
        because an earlier one stubbed a command for it. Register every stub a file needs
        in its own BeforeAll, and remove them in AfterAll with Remove-CommandStub. Stubs
        only ever exist on machines that lack the real command. Common parameter names
        (Verbose, ErrorAction, ...) are rejected because [CmdletBinding()] adds them.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Name,

        [string[]]$Parameter = @(),

        [string[]]$Switch = @(),

        [string]$PipelineParameter
    )

    $identifier = '^[A-Za-z_][A-Za-z0-9_]*$'
    # Spelled out rather than [PSCmdlet]::CommonParameters, which the 5.1 analyzer profile
    # cannot confirm. ProgressAction is PowerShell 7.4+.
    $reserved = 'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ProgressAction',
    'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable',
    'StubRemainingArguments'
    foreach ($paramName in @($Parameter) + @($Switch)) {
        if ($paramName -notmatch $identifier) { throw "Invalid parameter name '$paramName'." }
        if ($reserved -contains $paramName) { throw "Parameter name '$paramName' is a common parameter; the stub already has it." }
    }
    if ($PipelineParameter -and $Parameter -notcontains $PipelineParameter) {
        throw "PipelineParameter '$PipelineParameter' must also be listed in -Parameter."
    }

    foreach ($commandName in $Name) {
        if ($commandName -notmatch '^[A-Za-z][A-Za-z0-9_-]*$') { throw "Invalid command name '$commandName'." }

        $existing = Get-Command -Name $commandName -ErrorAction SilentlyContinue
        $isStub = $existing -and $existing.CommandType -eq 'Function' -and $existing.Definition -like "*$script:StubMarker*"
        if ($existing -and -not $isStub) {
            Write-Verbose "$commandName exists; not stubbing it."
            continue
        }

        $declarations = @(foreach ($p in $Parameter) {
                if ($p -eq $PipelineParameter) { "[Parameter(ValueFromPipeline = `$true)] `$$p" }
                else { "[Parameter()] `$$p" }
            })
        $declarations += foreach ($s in $Switch) { "[Parameter()] [switch] `$$s" }
        $declarations += '[Parameter(ValueFromRemainingArguments = $true)] $StubRemainingArguments'
        $body = "[CmdletBinding()] param($($declarations -join ', ')) throw ""'$commandName' $script:StubMarker; Mock it before calling it."""

        Set-Item -Path "Function:\global:$commandName" -Value ([scriptblock]::Create($body))
        Write-Verbose "Stubbed $commandName."
    }
}

function Remove-CommandStub {
    <#
    .SYNOPSIS
        Removes stubs made by Register-CommandStub, never a real command.

    .DESCRIPTION
        Deletes each global function whose body carries the Register-CommandStub marker.
        Call it in AfterAll so a file's stubs do not leak into the files that run after it.

    .PARAMETER Name
        Stub names to remove. Defaults to every stub in the session.

    .EXAMPLE
        AfterAll {
            Remove-CommandStub -Name Get-CimInstance
        }
    #>
    [CmdletBinding()]
    param(
        [string[]]$Name
    )

    $stubs = @(Get-ChildItem -Path Function:\ | Where-Object { $_.Definition -like "*$script:StubMarker*" })
    if ($Name) { $stubs = @($stubs | Where-Object { $Name -contains $_.Name }) }
    foreach ($stub in $stubs) {
        # Unqualified on purpose: Remove-Item ignores a 'global:' qualifier on the
        # Function: drive and removes nothing. This module defines no function with a
        # stub's name, so the lookup reaches the global stub.
        Remove-Item -LiteralPath "Function:\$($stub.Name)"
        Write-Verbose "Removed stub $($stub.Name)."
    }
}

Export-ModuleMember -Function Get-RepoRoot, Get-TrackedScript, Resolve-ScriptUnderTest, Get-ScriptFunctionDefinition, Register-CommandStub, Remove-CommandStub
