#Requires -Version 5.1
# Repository hygiene checks. These read file names and parse file contents; they never load or run any script.

BeforeDiscovery {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $unitTests = Get-ChildItem -Path (Join-Path $repoRoot 'Tests/Unit') -Filter '*.Tests.ps1' -File -ErrorAction SilentlyContinue
    $script:testCases = foreach ($test in $unitTests) {
        @{ TestFile = $test.Name; TargetName = $test.Name -replace '\.Tests\.ps1$', '' }
    }
}

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $script:targetNames = @(
        Get-ChildItem -Path (Join-Path $repoRoot 'Scripts'), (Join-Path $repoRoot 'Modules') -Recurse -File -Include '*.ps1', '*.psm1' |
            Where-Object { $_.Name -notmatch '\.Tests\.psm?1$' } |
            ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) }
    )
}

Describe 'Tests/Unit has no orphaned test files' {
    It '<TestFile> targets an existing file under Scripts/ or Modules/' -TestCases $script:testCases {
        param($TestFile, $TargetName)
        $script:targetNames | Should -Contain $TargetName -Because "$TestFile has no matching .ps1 or .psm1 under Scripts/ or Modules/; delete the test or restore the script"
    }
}

Describe 'No script loads a dependency from a working-directory-relative path' {
    # A path such as .\Helper.psm1 resolves against the caller's current directory, not the
    # script's folder, so the script breaks when run from anywhere else (#120). Anchor such
    # paths to $PSScriptRoot (Join-Path $PSScriptRoot 'Helper.psm1') or import by module name.
    # Import-Module is also checked by argument, so an extensionless module path (.\Helper,
    # ..\Mods\Helper, lib\Helper) is caught directly, through a variable, or through a splat.
    # Scripts are parsed, never run. Comments (including help examples) are not in the AST.
    # Manifests (.psd1) are not scanned: their RootModule, NestedModules and ScriptsToProcess
    # paths resolve against the manifest's folder. 'using module .\x.psm1' is skipped for the
    # same reason: it resolves against the script's folder.
    BeforeAll {
        $script:relativePattern = '^\.{1,2}[\\/].*\.ps[dm]?1$'
        $script:anchorVariables = @('PSScriptRoot', 'PSCommandPath')

        function Test-AnchoredElement {
            # True when the AST element references $PSScriptRoot or $PSCommandPath.
            param([System.Management.Automation.Language.Ast]$Element)
            $names = $script:anchorVariables
            $found = $Element.Find({
                    param($node)
                    $node -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $names -contains $node.VariablePath.UserPath
                }, $true)
            return ($null -ne $found)
        }

        function Test-CurrentDirectoryElement {
            # True when the AST element is the current directory: a '.' or '.\x' literal, $PWD,
            # or a Get-Location (pwd, gl) call.
            param([System.Management.Automation.Language.Ast]$Element)
            if ($Element -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                $Element -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
                if ($Element.Value -match '^\.{1,2}([\\/]|$)') { return $true }
            }
            $found = $Element.Find({
                    param($node)
                    ($node -is [System.Management.Automation.Language.VariableExpressionAst] -and $node.VariablePath.UserPath -eq 'PWD') -or
                    ($node -is [System.Management.Automation.Language.CommandAst] -and @('Get-Location', 'pwd', 'gl') -contains $node.GetCommandName())
                }, $true)
            return ($null -ne $found)
        }

        function Get-JoinPathParentElement {
            # Returns the element bound to Join-Path's -Path parameter (named or first positional).
            param([System.Management.Automation.Language.CommandAst]$Command)
            $elements = $Command.CommandElements
            $i = 1
            while ($i -lt $elements.Count) {
                $element = $elements[$i]
                if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
                    $isPath = 'Path'.StartsWith($element.ParameterName, [System.StringComparison]::OrdinalIgnoreCase) -or
                    @('LiteralPath', 'PSPath') -contains $element.ParameterName
                    if ($null -ne $element.Argument) {
                        if ($isPath) { return $element.Argument }
                        $i++
                        continue
                    }
                    if ($isPath) {
                        if ($i + 1 -lt $elements.Count) { return $elements[$i + 1] }
                        return $null
                    }
                    # -Resolve is a switch; every other Join-Path parameter takes a value.
                    if ('Resolve'.StartsWith($element.ParameterName, [System.StringComparison]::OrdinalIgnoreCase)) { $i++ } else { $i += 2 }
                    continue
                }
                return $element
            }
            return $null
        }

        $script:importCommands = @('Import-Module', 'ipmo')
        # Import-Module switches (5.1 and 7); every other Import-Module parameter takes a value.
        $script:importSwitches = @('Global', 'Force', 'SkipEditionCheck', 'PassThru', 'AsCustomObject', 'DisableNameChecking', 'NoClobber', 'UseWindowsPowerShell', 'Verbose', 'Debug')

        function Test-ParameterPrefix {
            # True when $Name is a prefix of $Full (PowerShell accepts unambiguous parameter prefixes).
            param([string]$Full, [string]$Name)
            return ($Name.Length -gt 0 -and $Full.StartsWith($Name, [System.StringComparison]::OrdinalIgnoreCase))
        }

        function Test-RelativeModulePath {
            # True when a module name resolves against the current directory: .\x, ..\x, ./x, '.',
            # or any unrooted name with a path separator (lib\x). Bare names such as Pester or
            # Microsoft.PowerShell.Utility are looked up on PSModulePath and are not paths.
            param([string]$Value)
            if ($Value -match '^\.{1,2}([\\/]|$)') { return $true }
            if ($Value -notmatch '[\\/]') { return $false }
            return ($Value -notmatch '^([A-Za-z]:|[\\/]|~)')
        }

        function Get-AssignedValue {
            # Returns the right-hand side of every assignment to $Name anywhere in the file.
            # Scope-unaware on purpose: any relative value ever assigned is suspect.
            param([System.Management.Automation.Language.Ast]$Ast, [string]$Name)
            $Ast.FindAll({
                    param($node)
                    if ($node -isnot [System.Management.Automation.Language.AssignmentStatementAst]) { return $false }
                    $target = $node.Left.Find({ param($v) $v -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)
                    $null -ne $target -and $target.VariablePath.UserPath -eq $Name
                }, $true) | ForEach-Object { $_.Right }
        }

        function Test-RelativeModuleElement {
            # True when an AST element given to Import-Module as a module name or specification
            # resolves against the current directory. Follows lists, parentheses, Join-Path,
            # ModuleSpecification hashtables, and variables assigned in the same file.
            param($Element, [System.Management.Automation.Language.Ast]$Ast, [int]$Depth = 0)
            if ($null -eq $Element -or $Depth -gt 8) { return $false }
            $next = $Depth + 1
            if ($Element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                return (Test-RelativeModulePath -Value $Element.Value)
            }
            if ($Element -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
                # "$PSScriptRoot\x" or "$env:X\x" depend on a variable; only a leading .\ is known relative.
                if (Test-AnchoredElement -Element $Element) { return $false }
                return ($Element.Value -match '^\.{1,2}([\\/]|$)')
            }
            if ($Element -is [System.Management.Automation.Language.VariableExpressionAst]) {
                foreach ($value in @(Get-AssignedValue -Ast $Ast -Name $Element.VariablePath.UserPath)) {
                    if (Test-RelativeModuleElement -Element $value -Ast $Ast -Depth $next) { return $true }
                }
                return $false
            }
            if ($Element -is [System.Management.Automation.Language.HashtableAst]) {
                # A ModuleSpecification: @{ ModuleName = '.\x'; ModuleVersion = '1.0' }.
                foreach ($pair in $Element.KeyValuePairs) {
                    if ($pair.Item1.Value -eq 'ModuleName' -and (Test-RelativeModuleElement -Element $pair.Item2 -Ast $Ast -Depth $next)) { return $true }
                }
                return $false
            }
            if ($Element -is [System.Management.Automation.Language.CommandAst]) {
                if ($Element.GetCommandName() -ne 'Join-Path') { return $false }
                $parentPath = Get-JoinPathParentElement -Command $Element
                return ($null -ne $parentPath -and -not (Test-AnchoredElement -Element $parentPath) -and (Test-CurrentDirectoryElement -Element $parentPath))
            }
            $children = @()
            if ($Element -is [System.Management.Automation.Language.ArrayLiteralAst]) { $children = $Element.Elements }
            elseif ($Element -is [System.Management.Automation.Language.ArrayExpressionAst]) { $children = $Element.SubExpression.Statements }
            elseif ($Element -is [System.Management.Automation.Language.ParenExpressionAst]) { $children = @($Element.Pipeline) }
            elseif ($Element -is [System.Management.Automation.Language.CommandExpressionAst]) { $children = @($Element.Expression) }
            elseif ($Element -is [System.Management.Automation.Language.ConvertExpressionAst]) { $children = @($Element.Child) }
            elseif ($Element -is [System.Management.Automation.Language.PipelineAst] -and $Element.PipelineElements.Count -eq 1) { $children = $Element.PipelineElements }
            foreach ($child in $children) {
                if (Test-RelativeModuleElement -Element $child -Ast $Ast -Depth $next) { return $true }
            }
            return $false
        }

        function Test-RelativeImportCommand {
            # True when an Import-Module call loads a module by a working-directory-relative path,
            # through -Name, -FullyQualifiedName, the first positional argument, a splatted
            # hashtable or array, or pipeline input. Other parameters (-Prefix, ...) are ignored.
            param([System.Management.Automation.Language.CommandAst]$Command, [System.Management.Automation.Language.Ast]$Ast)
            $elements = $Command.CommandElements
            $positionalSeen = $false
            $i = 1
            while ($i -lt $elements.Count) {
                $element = $elements[$i]
                if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
                    $name = $element.ParameterName
                    $isModule = (Test-ParameterPrefix -Full 'Name' -Name $name) -or (Test-ParameterPrefix -Full 'FullyQualifiedName' -Name $name)
                    if ($null -ne $element.Argument) {
                        if ($isModule -and (Test-RelativeModuleElement -Element $element.Argument -Ast $Ast)) { return $true }
                        $i++
                        continue
                    }
                    if ($isModule) {
                        if ($i + 1 -lt $elements.Count -and (Test-RelativeModuleElement -Element $elements[$i + 1] -Ast $Ast)) { return $true }
                        $i += 2
                        continue
                    }
                    $isSwitch = @($script:importSwitches | Where-Object { Test-ParameterPrefix -Full $_ -Name $name }).Count -gt 0
                    if ($isSwitch) { $i++ } else { $i += 2 }
                    continue
                }
                if ($element -is [System.Management.Automation.Language.VariableExpressionAst] -and $element.Splatted) {
                    foreach ($value in @(Get-AssignedValue -Ast $Ast -Name $element.VariablePath.UserPath)) {
                        $splat = $value.Find({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] -or $n -is [System.Management.Automation.Language.ArrayExpressionAst] -or $n -is [System.Management.Automation.Language.ArrayLiteralAst] }, $true)
                        if ($splat -is [System.Management.Automation.Language.HashtableAst]) {
                            foreach ($pair in $splat.KeyValuePairs) {
                                $key = [string]$pair.Item1.Value
                                if (((Test-ParameterPrefix -Full 'Name' -Name $key) -or (Test-ParameterPrefix -Full 'FullyQualifiedName' -Name $key)) -and
                                    (Test-RelativeModuleElement -Element $pair.Item2 -Ast $Ast)) { return $true }
                            }
                        } elseif ($null -ne $splat -and (Test-RelativeModuleElement -Element $splat -Ast $Ast)) { return $true }
                    }
                    $i++
                    continue
                }
                if (-not $positionalSeen) {
                    $positionalSeen = $true
                    if (Test-RelativeModuleElement -Element $element -Ast $Ast) { return $true }
                }
                $i++
            }
            # '.\x' | Import-Module: the module name arrives as pipeline input.
            $pipeline = $Command.Parent
            if ($pipeline -is [System.Management.Automation.Language.PipelineAst]) {
                $index = $pipeline.PipelineElements.IndexOf($Command)
                if ($index -gt 0 -and (Test-RelativeModuleElement -Element $pipeline.PipelineElements[$index - 1] -Ast $Ast)) { return $true }
            }
            return $false
        }

        function Get-RelativeImportOffender {
            # Lists 'file:line: text' for every working-directory-relative script path under
            # <Root>/Scripts and <Root>/Modules, and 'file: parse error ...' for unparsable files.
            param([string]$Root)
            $folders = @('Scripts', 'Modules') | ForEach-Object { Join-Path $Root $_ } | Where-Object { Test-Path -LiteralPath $_ }
            if (-not $folders) { return }
            $files = Get-ChildItem -Path $folders -Recurse -File -Include '*.ps1', '*.psm1'
            foreach ($file in $files) {
                $relative = $file.FullName.Substring($Root.Length).TrimStart('\', '/')
                $tokens = $null
                $parseErrors = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
                if ($parseErrors) {
                    # A partially parsed file could hide an import, so it never passes silently.
                    '{0}:{1}: parse error: {2}' -f $relative, $parseErrors[0].Extent.StartLineNumber, $parseErrors[0].Message
                    continue
                }
                $strings = $ast.FindAll({
                        param($node)
                        $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                        $node -is [System.Management.Automation.Language.ExpandableStringExpressionAst]
                    }, $true)
                foreach ($string in $strings) {
                    if ($string.Value -notmatch $script:relativePattern) { continue }
                    $parent = $string.Parent
                    if ($parent -is [System.Management.Automation.Language.UsingStatementAst]) { continue }
                    # Join-Path $PSScriptRoot '.\x.psm1' is anchored, so its child path is fine.
                    # Any other parent path (., $PWD, '.\lib') is still relative to the caller.
                    if ($parent -is [System.Management.Automation.Language.CommandAst] -and $parent.GetCommandName() -eq 'Join-Path') {
                        $parentPath = Get-JoinPathParentElement -Command $parent
                        if ($null -ne $parentPath -and $parentPath -ne $string -and (Test-AnchoredElement -Element $parentPath)) { continue }
                    }
                    '{0}:{1}: {2}' -f $relative, $string.Extent.StartLineNumber, $string.Extent.Text
                }
                # Join-Path '.\lib' 'Helper.psm1' or Join-Path $PWD 'Helper.psm1': no single string
                # is a .\ path, but the parent path is the current directory.
                $joins = $ast.FindAll({
                        param($node)
                        $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Join-Path'
                    }, $true)
                foreach ($join in $joins) {
                    $parentPath = Get-JoinPathParentElement -Command $join
                    if ($null -eq $parentPath -or -not (Test-CurrentDirectoryElement -Element $parentPath)) { continue }
                    $children = @($join.CommandElements | Select-Object -Skip 1 | Where-Object {
                            $_ -ne $parentPath -and
                            ($_ -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                            $_ -is [System.Management.Automation.Language.ExpandableStringExpressionAst])
                        })
                    # A .\ child is already reported by the string check above.
                    if (@($children | Where-Object { $_.Value -match $script:relativePattern }).Count -gt 0) { continue }
                    if (@($children | Where-Object { $_.Value -match '\.ps[dm]?1$' }).Count -eq 0) { continue }
                    '{0}:{1}: {2}' -f $relative, $join.Extent.StartLineNumber, $join.Extent.Text
                }
                # Import-Module .\Helper, -Name ..\Mods\Helper, a variable or splat: a module
                # folder or name has no extension, so the string checks above miss it.
                $imports = $ast.FindAll({
                        param($node)
                        $node -is [System.Management.Automation.Language.CommandAst] -and $script:importCommands -contains $node.GetCommandName()
                    }, $true)
                foreach ($import in $imports) {
                    if (Test-RelativeImportCommand -Command $import -Ast $ast) {
                        '{0}:{1}: {2}' -f $relative, $import.Extent.StartLineNumber, $import.Extent.Text
                    }
                }
            }
        }
    }

    It 'no code under Scripts/ or Modules/ loads a script or module from a .\ or ./ path' {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $offenders = @(Get-RelativeImportOffender -Root $repoRoot | Select-Object -Unique)
        $offenders | Should -BeNullOrEmpty -Because ('these load a file relative to the current directory, or do not parse; anchor them to $PSScriptRoot: ' + ($offenders -join '; '))
    }

    Context 'detection on planted fixtures' {
        It 'flags <Name>' -TestCases @(
            @{ Name = 'a dot-slash import'; Code = 'Import-Module .\Helper.psm1' }
            @{ Name = 'a dot-source'; Code = '. .\Helper.ps1' }
            @{ Name = 'Join-Path from $PWD'; Code = 'Import-Module (Join-Path $PWD ''.\Helper.psm1'')' }
            @{ Name = 'Join-Path from a relative parent'; Code = 'Import-Module (Join-Path ''.\lib'' ''Helper.psm1'')' }
            @{ Name = 'Join-Path with a relative child and a relative -Path'; Code = 'Import-Module (Join-Path -ChildPath ''.\Helper.psm1'' -Path ''lib'')' }
            @{ Name = 'Join-Path with $PSScriptRoot only as the child'; Code = 'Import-Module (Join-Path ''.\lib'' $PSScriptRoot ''.\Helper.psm1'')' }
            @{ Name = 'Join-Path from $PWD with a bare child'; Code = 'Import-Module (Join-Path $PWD ''Helper.psm1'')' }
            @{ Name = 'Join-Path from Get-Location'; Code = '. (Join-Path (Get-Location) ''Helper.ps1'')' }
            @{ Name = 'a file that does not parse'; Code = "function Broken {`n    if (" }
            @{ Name = 'a -Name import with an extension'; Code = 'Import-Module -Name .\Helper.psm1' }
            @{ Name = 'an extensionless positional import'; Code = 'Import-Module .\Helper' }
            @{ Name = 'an extensionless -Name import'; Code = 'Import-Module -Name .\Helper' }
            @{ Name = 'a -Name import after a switch'; Code = 'Import-Module -Force -Name ./Helper' }
            @{ Name = 'a parent-folder module import'; Code = 'Import-Module ..\Mods\Helper' }
            @{ Name = 'a relative path with no leading dot'; Code = 'Import-Module lib\Helper' }
            @{ Name = 'a relative path in a name list'; Code = 'Import-Module Pester, .\Helper' }
            @{ Name = 'the ipmo alias'; Code = 'ipmo .\Helper' }
            @{ Name = 'a relative path held in a variable'; Code = "`$helper = '.\Helper'`nImport-Module `$helper" }
            @{ Name = 'a relative path in a splatted hashtable'; Code = "`$importArgs = @{ Name = '.\Helper'; Force = `$true }`nImport-Module @importArgs" }
            @{ Name = 'a relative -FullyQualifiedName ModuleName'; Code = 'Import-Module -FullyQualifiedName @{ ModuleName = ''.\Helper''; ModuleVersion = ''1.0'' }' }
            @{ Name = 'a relative path piped to Import-Module'; Code = '''.\Helper'' | Import-Module' }
            @{ Name = 'an extensionless Join-Path from $PWD'; Code = 'Import-Module (Join-Path $PWD ''Helper'')' }
        ) {
            param($Name, $Code)
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $root 'Scripts') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'Scripts/Case.ps1') -Value $Code -Encoding UTF8
            @(Get-RelativeImportOffender -Root $root).Count | Should -BeGreaterThan 0 -Because "$Name loads relative to the current directory or hides code behind a parse error"
        }

        It 'does not flag <Name>' -TestCases @(
            @{ Name = 'Join-Path $PSScriptRoot with a dot-slash child'; Code = 'Import-Module (Join-Path $PSScriptRoot ''.\Helper.psm1'')' }
            @{ Name = 'Join-Path -Path $PSScriptRoot -ChildPath'; Code = 'Import-Module (Join-Path -ChildPath ''.\Helper.psm1'' -Path $PSScriptRoot)' }
            @{ Name = 'Join-Path from $PSCommandPath''s folder'; Code = 'Import-Module (Join-Path (Split-Path $PSCommandPath) ''.\Helper.psm1'')' }
            @{ Name = 'an interpolated $PSScriptRoot path'; Code = 'Import-Module "$PSScriptRoot\Helper.psm1"' }
            @{ Name = 'using module with a relative path'; Code = 'using module .\Helper.psm1' }
            @{ Name = 'an import by module name'; Code = 'Import-Module Helper' }
            @{ Name = 'Import-Module Pester'; Code = 'Import-Module Pester' }
            @{ Name = 'Import-Module MsiTools -Force'; Code = 'Import-Module MsiTools -Force' }
            @{ Name = 'a dotted module name'; Code = 'Import-Module -Name Microsoft.PowerShell.Utility' }
            @{ Name = 'an extensionless Join-Path $PSScriptRoot import'; Code = 'Import-Module (Join-Path $PSScriptRoot ''Helper'')' }
            @{ Name = 'an extensionless interpolated $PSScriptRoot import'; Code = 'Import-Module "$PSScriptRoot\Helper"' }
            @{ Name = 'an absolute module path'; Code = 'Import-Module -Name ''C:\Modules\Helper''' }
            @{ Name = 'Get-Module -ListAvailable on a relative path'; Code = 'Get-Module -ListAvailable -Name .\Helper' }
            @{ Name = 'a relative variable that is never imported'; Code = "`$helper = '.\Helper'`nGet-Item `$helper`nImport-Module Pester" }
            @{ Name = 'a relative -Prefix value'; Code = 'Import-Module -Prefix ./X -Name Pester' }
        ) {
            param($Name, $Code)
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $root 'Scripts') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'Scripts/Case.ps1') -Value $Code -Encoding UTF8
            @(Get-RelativeImportOffender -Root $root) | Should -BeNullOrEmpty
        }

        It 'does not scan module manifests, whose paths resolve against the manifest folder' {
            $root = Join-Path $TestDrive 'manifest'
            New-Item -ItemType Directory -Path (Join-Path $root 'Modules/M') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'Modules/M/M.psd1') -Value "@{ RootModule = '.\M.psm1'; NestedModules = @('.\Sub.psm1'); ScriptsToProcess = @('.\Init.ps1') }" -Encoding UTF8
            @(Get-RelativeImportOffender -Root $root) | Should -BeNullOrEmpty
        }
    }
}
