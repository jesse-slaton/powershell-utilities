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
            }
        }
    }

    It 'no string in code under Scripts/ or Modules/ is a .\ or ./ path to a .ps1, .psm1 or .psd1 file' {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $offenders = @(Get-RelativeImportOffender -Root $repoRoot)
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
