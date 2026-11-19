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

    .EXAMPLE
        $scriptPath = Resolve-ScriptUnderTest -Name $PSCommandPath
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $baseName = [System.IO.Path]::GetFileName($Name) -replace '\.Tests\.ps1$', '' -replace '\.psm?1$', ''
    $found = @(Get-TrackedScript | Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $baseName })

    if ($found.Count -eq 0) { throw "No script named '$baseName' under Scripts/ or Modules/." }
    if ($found.Count -gt 1) { throw "More than one script named '$baseName': $($found.FullName -join ', ')" }
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

    .PARAMETER Path
        Path of the .ps1 or .psm1 file.

    .PARAMETER Name
        Only include these function names. Defaults to every top-level function.

    .EXAMPLE
        BeforeAll {
            Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
            . (Get-ScriptFunctionDefinition -Path (Resolve-ScriptUnderTest -Name $PSCommandPath))
        }
    #>
    [CmdletBinding()]
    [OutputType([scriptblock])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string[]]$Name
    )

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw "Cannot parse '$Path': $($errors[0].Message)" }

    $functions = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false))
    if ($Name) { $functions = @($functions | Where-Object { $Name -contains $_.Name }) }
    if ($functions.Count -eq 0) { throw "No matching top-level functions in '$Path'." }

    [scriptblock]::Create(($functions | ForEach-Object { $_.Extent.Text }) -join [Environment]::NewLine)
}

Export-ModuleMember -Function Get-RepoRoot, Get-TrackedScript, Resolve-ScriptUnderTest, Get-ScriptFunctionDefinition
