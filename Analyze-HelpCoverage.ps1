<#
.SYNOPSIS
    Grades comment-based help in Scripts/ and Modules/ against the repository help standard.

.DESCRIPTION
    Parses every .ps1 and .psm1 file under Scripts/ and Modules/ with the PowerShell
    language parser (no file is executed or dot-sourced) and grades its help against
    the standard in README.md ("Comment-based help standard"):

    - .SYNOPSIS and .DESCRIPTION
    - one .PARAMETER for every declared parameter
    - at least one .EXAMPLE, or two when the script or function takes parameters
    - .NOTES (prerequisites such as admin rights, a vendor agent, or required modules)

    A .ps1 file is graded once, on its script-level help, except a function library: a
    .ps1 with no script-level help whose top-level statements are all function definitions
    (no param() block, no begin/process blocks, no other top-level code) is graded per
    function, since the standard allows help as the first thing inside a function body.
    Libraries include module function files such as Modules/<Name>/Public/*.ps1 and
    Private/*.ps1; Private helpers are graded too, because the standard covers every .ps1
    under Modules/. A .ps1 that also runs code at top level is graded at script level,
    because its help must describe what running the script does; when such a file has no
    script-level help but defines functions, its Missing list starts with "top-level code
    outside functions; graded at script level", so the report says why any function help
    was not counted. A .psm1 file is graded per exported function:
    functions named in Export-ModuleMember -Function, or every top-level function when
    the module has no Export-ModuleMember call.

    Each item is Complete (meets every rule), Partial (has a .SYNOPSIS but misses at
    least one rule), or None (no .SYNOPSIS). Tests/ is exempt and never scanned.

.PARAMETER RepoRoot
    Repository root that contains Scripts/ and Modules/. Defaults to the folder this
    script lives in.

.PARAMETER OutputPath
    Path of the JSON report. Defaults to help-coverage-report.json in RepoRoot (the
    file is gitignored). Pass an empty string to skip writing the report.

.PARAMETER FailOnIncomplete
    Exit with code 1 when any item is not Complete. Use this once help coverage is
    meant to be a blocking CI check.

.EXAMPLE
    .\Analyze-HelpCoverage.ps1

    Prints a summary and the files missing help, and writes help-coverage-report.json.

.EXAMPLE
    .\Analyze-HelpCoverage.ps1 -OutputPath '' -FailOnIncomplete

    Prints the summary without writing a report and exits 1 if any item is incomplete.

.NOTES
    Requires PowerShell 5.1 or later. Reads files only; makes no changes outside
    OutputPath.
#>

[CmdletBinding()]
param(
    [string]$RepoRoot = $PSScriptRoot,

    [AllowEmptyString()]
    [string]$OutputPath,

    [switch]$FailOnIncomplete
)

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot -ErrorAction Stop).ProviderPath.TrimEnd('\', '/')

if (-not $PSBoundParameters.ContainsKey('OutputPath')) {
    $OutputPath = Join-Path $RepoRoot 'help-coverage-report.json'
}

function Get-HelpGrade {
    <#
    .SYNOPSIS
        Grades one help block against the standard and returns Complete, Partial, or None plus the missing rules.
    #>
    param(
        [System.Management.Automation.Language.CommentHelpInfo]$Help,
        [string[]]$ParameterNames
    )

    $missing = New-Object System.Collections.Generic.List[string]
    $hasSynopsis = $Help -and -not [string]::IsNullOrWhiteSpace($Help.Synopsis)
    if (-not $hasSynopsis) { $missing.Add('SYNOPSIS') }
    if (-not $Help -or [string]::IsNullOrWhiteSpace($Help.Description)) { $missing.Add('DESCRIPTION') }

    $documented = if ($Help) { @($Help.Parameters.Keys | ForEach-Object { $_.ToUpperInvariant() }) } else { @() }
    foreach ($name in $ParameterNames) {
        if ($documented -notcontains $name.ToUpperInvariant()) { $missing.Add("PARAMETER $name") }
    }

    $requiredExamples = if ($ParameterNames.Count -gt 0) { 2 } else { 1 }
    $exampleCount = if ($Help) { $Help.Examples.Count } else { 0 }
    if ($exampleCount -lt $requiredExamples) {
        $missing.Add("EXAMPLE (have $exampleCount, need $requiredExamples)")
    }

    if (-not $Help -or [string]::IsNullOrWhiteSpace($Help.Notes)) { $missing.Add('NOTES') }

    $grade = if (-not $hasSynopsis) { 'None' } elseif ($missing.Count -eq 0) { 'Complete' } else { 'Partial' }
    [pscustomobject]@{ Grade = $grade; Missing = @($missing) }
}

function Get-ParameterName {
    param([System.Management.Automation.Language.ParameterAst[]]$Parameter)
    @($Parameter | Where-Object { $_ } | ForEach-Object { $_.Name.VariablePath.UserPath })
}

function Get-FunctionParameterName {
    param([System.Management.Automation.Language.FunctionDefinitionAst]$Function)
    $params = if ($Function.Body.ParamBlock) { $Function.Body.ParamBlock.Parameters } else { $Function.Parameters }
    Get-ParameterName $params
}

function Test-FunctionLibrary {
    <#
    .SYNOPSIS
        True when a parsed .ps1 holds only function definitions: no param() block, no
        begin/process/dynamicparam blocks, and every top-level statement defines a function.
    #>
    param([System.Management.Automation.Language.ScriptBlockAst]$Ast)
    if ($Ast.ParamBlock -or $Ast.BeginBlock -or $Ast.ProcessBlock -or $Ast.DynamicParamBlock) { return $false }
    if (-not $Ast.EndBlock -or $Ast.EndBlock.Statements.Count -eq 0) { return $false }
    foreach ($statement in $Ast.EndBlock.Statements) {
        if ($statement -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { return $false }
    }
    $true
}

$scanRoots = @('Scripts', 'Modules') | ForEach-Object { Join-Path $RepoRoot $_ } | Where-Object { Test-Path $_ }
$files = @(Get-ChildItem -Path $scanRoots -Recurse -File -Include '*.ps1', '*.psm1' | Sort-Object FullName)

$items = foreach ($file in $files) {
    $relative = $file.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)

    if ($parseErrors.Count -gt 0) {
        [pscustomobject]@{ File = $relative; Function = $null; Grade = 'None'; Missing = @("parse error: $($parseErrors[0].Message)") }
        continue
    }

    if ($file.Extension -eq '.psm1') {
        $functions = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false))

        $exportCalls = @($ast.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Export-ModuleMember'
                }, $true))
        if ($exportCalls.Count -gt 0) {
            $exported = foreach ($call in $exportCalls) {
                $call.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $_ -is [System.Management.Automation.Language.ArrayLiteralAst] } |
                    ForEach-Object { $_.SafeGetValue() }
            }
            $exported = @($exported | ForEach-Object { $_ } | Where-Object { $_ -is [string] -and $_ -ne 'Export-ModuleMember' })
            # Names passed in variables cannot be resolved statically; grade every function then.
            if ($exported.Count -gt 0 -and $exported -notcontains '*') {
                $functions = @($functions | Where-Object { $exported -contains $_.Name })
            }
        }

        if ($functions.Count -eq 0) {
            # The standard applies per exported function; a module that defines none has nothing to grade.
            Write-Verbose "$relative defines no functions to grade; skipped."
            continue
        }

        foreach ($function in $functions) {
            $result = Get-HelpGrade -Help $function.GetHelpContent() -ParameterNames (Get-FunctionParameterName $function)
            [pscustomobject]@{ File = $relative; Function = $function.Name; Grade = $result.Grade; Missing = $result.Missing }
        }
    }
    else {
        $scriptHelp = $ast.GetHelpContent()
        $functions = @()
        if (-not $scriptHelp -and (Test-FunctionLibrary $ast)) {
            # A function library: nothing but function definitions. The standard allows help as
            # the first thing inside each function body, so grade the functions.
            $functions = @($ast.EndBlock.Statements)
        }

        if ($functions.Count -gt 0) {
            foreach ($function in $functions) {
                $result = Get-HelpGrade -Help $function.GetHelpContent() -ParameterNames (Get-FunctionParameterName $function)
                [pscustomobject]@{ File = $relative; Function = $function.Name; Grade = $result.Grade; Missing = $result.Missing }
            }
        }
        else {
            $params = if ($ast.ParamBlock) { $ast.ParamBlock.Parameters } else { @() }
            $result = Get-HelpGrade -Help $scriptHelp -ParameterNames (Get-ParameterName $params)
            $scriptMissing = @($result.Missing)
            $definesFunctions = $ast.EndBlock -and @($ast.EndBlock.Statements | Where-Object {
                    $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] }).Count -gt 0
            if (-not $scriptHelp -and $definesFunctions) {
                # Say why any function help in the file was not counted, so the report does not
                # read as if the file had no help at all.
                $scriptMissing = @('top-level code outside functions; graded at script level') + $scriptMissing
            }
            [pscustomobject]@{ File = $relative; Function = $null; Grade = $result.Grade; Missing = $scriptMissing }
        }
    }
}
$items = @($items)

$total = $items.Count
$byGrade = @{}
foreach ($grade in 'Complete', 'Partial', 'None') { $byGrade[$grade] = @($items | Where-Object Grade -EQ $grade) }

function Format-Percent([int]$Count) { if ($total) { [math]::Round($Count / $total * 100, 1) } else { 0 } }

Write-Host "`n=== Comment-based help coverage (Scripts/ and Modules/) ===" -ForegroundColor Cyan
Write-Host "Files scanned: $($files.Count)   Items graded: $total (one per .ps1 or .ps1 library function, one per exported .psm1 function)"
Write-Host "Complete: $($byGrade.Complete.Count) ($(Format-Percent $byGrade.Complete.Count)%)" -ForegroundColor Green
Write-Host "Partial:  $($byGrade.Partial.Count) ($(Format-Percent $byGrade.Partial.Count)%)" -ForegroundColor Yellow
Write-Host "None:     $($byGrade.None.Count) ($(Format-Percent $byGrade.None.Count)%)" -ForegroundColor Red

Write-Host "`n=== Items without help, by folder ===" -ForegroundColor Yellow
$byGrade.None | Group-Object { ($_.File -split '/')[0..1] -join '/' } | Sort-Object Count -Descending |
    ForEach-Object { Write-Host ("{0}: {1}" -f $_.Name, $_.Count) -ForegroundColor Yellow }

if ($OutputPath) {
    [ordered]@{
        Standard     = 'README.md#comment-based-help-standard'
        FilesScanned = $files.Count
        ItemsGraded  = $total
        Complete     = $byGrade.Complete.Count
        Partial      = $byGrade.Partial.Count
        None         = $byGrade.None.Count
        Items        = $items
    } | ConvertTo-Json -Depth 4 | Set-Content -Path $OutputPath -Encoding UTF8
    Write-Host "`nReport written to: $OutputPath" -ForegroundColor Green
}

if ($FailOnIncomplete -and ($byGrade.Partial.Count + $byGrade.None.Count) -gt 0) {
    Write-Error "$($byGrade.Partial.Count + $byGrade.None.Count) item(s) do not meet the help standard."
    exit 1
}
