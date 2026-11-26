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
    #
    # One detector. It finds each LOADING SITE and asks one resolver whether the path given
    # there is rooted in the current directory.
    #   Loading sites: dot-source (. <path>), the call operator (& <path>), running a script
    #     by path (.\x.ps1 -Arg), all three only for a path that may name a .ps1/.psm1/.psd1
    #     (see below), and Import-Module / ipmo (-Name, -FullyQualifiedName, the first
    #     positional argument, a splatted hashtable or array, pipeline input).
    #   The resolver follows: strings in every quote style, here-strings included ("lib\$x" is
    #     judged by its static text: the leading text or leading variable for the root, the
    #     trailing text for the extension), + concatenation (the leftmost operand for the root,
    #     the rightmost for the extension), variables assigned with = anywhere in the file
    #     (scope-unaware), lists, member access ($PWD.Path), ModuleSpecification hashtables,
    #     Join-Path (by its parent path), $PWD, and Get-Location (pwd, gl). Before any of that, every expression it inspects is unwrapped,
    #     recursively, from ( ), $( ), @( ), a cast ([string]x) and a one-element pipeline, so
    #     (Join-Path ($PWD) ([string]('x.ps1'))) is read as Join-Path $PWD 'x.ps1'.
    #   Run with . or &, a path from a current-directory root passes only when it is STATICALLY
    #     known not to be a script ('tool.exe', "$tool.exe", a variable only ever assigned such a
    #     value). A file name that cannot be resolved (& (Join-Path $PWD $file), "$PWD\$name",
    #     $PWD.Path + $x) is flagged: anchor the root to $PSScriptRoot instead.
    #   Command names match in any case and with a module qualifier
    #     (Microsoft.PowerShell.Core\Import-Module); parameters match by any prefix (-N) and in
    #     -Name:value form. $PSScriptRoot and $PSCommandPath anchor a path; a variable never
    #     assigned in the file ($env:X, a parameter) is treated as unknown and passes.
    #   A path counts as current-directory-rooted when it starts with .\ or ..\ (or is . or
    #     ..), is drive-relative (C:Helper resolves against the current directory on drive C),
    #     starts with a single \ or / (the root of the CURRENT drive, which moves with
    #     Set-Location), or is unrooted with a separator: lib\Helper for Import-Module,
    #     lib\x.ps1 for . and &. A Join-Path parent counts when it is any unrooted path ('lib').
    #     Rooted, and allowed: C:\x, C:/x, \\server\share\x, a PowerShell drive (Env:,
    #     TestDrive:), ~, and a bare C: as a Join-Path parent (Join-Path C: x is C:\x).
    # NOT detected: native executables (.\tool.exe); a relative path used only by a
    # non-loading command (Test-Path, Copy-Item, Get-Content, Get-Module -ListAvailable), or
    # never used; paths handed to a child process (pwsh -File .\x.ps1, Start-Process);
    # foreach/parameter-bound variables; a relative path turned absolute by another command
    # (Import-Module (Resolve-Path .\x), Convert-Path, Get-Item); a splatted Join-Path; a
    # pipeline of several commands ((Get-Location | Select-Object -ExpandProperty Path)); paths
    # built with -f, -join, -replace or [System.IO.Path]::Combine; a "...$x" whose static prefix is only \ or C: (what follows
    # may complete \\server or C:\, so it is unknown). Dynamic code is out of scope:
    # Invoke-Expression, [scriptblock]::Create, and code inside strings. Comments (including
    # help examples) are not in the AST.
    # Manifests (.psd1) are not scanned: their RootModule, NestedModules and ScriptsToProcess
    # paths resolve against the manifest's folder. 'using module .\x.psm1' is not a loading
    # site for the same reason: it resolves against the script's folder.
    # Scripts are parsed, never run.
    BeforeAll {
        $script:anchorVariables = @('PSScriptRoot', 'PSCommandPath')
        $script:locationCommands = @('Get-Location', 'pwd', 'gl')
        $script:scriptExtension = '\.ps[dm]?1$'
        $script:importCommands = @('Import-Module', 'ipmo')
        # Import-Module switches (5.1 and 7); every other Import-Module parameter takes a value.
        $script:importSwitches = @('Global', 'Force', 'SkipEditionCheck', 'PassThru', 'AsCustomObject', 'DisableNameChecking', 'NoClobber', 'UseWindowsPowerShell', 'Verbose', 'Debug')

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

        function Test-ParameterPrefix {
            # True when $Name is a prefix of $Full (PowerShell accepts unambiguous parameter prefixes).
            param([string]$Full, [string]$Name)
            return ($Name.Length -gt 0 -and $Full.StartsWith($Name, [System.StringComparison]::OrdinalIgnoreCase))
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

        function Test-RelativePathText {
            # True when a literal path resolves against the current directory. $Mode is the use:
            # Module (Import-Module: a bare name is looked up on PSModulePath, lib\x is a path),
            # Command (. and &: only a .ps1/.psm1/.psd1 path counts; a bare name or Module\Command
            # is a command, and an .exe is not a script dependency),
            # Path (a Join-Path parent: any unrooted path, 'lib' included).
            param([string]$Value, [string]$Mode)
            if ($Mode -eq 'Command' -and $Value -notmatch $script:scriptExtension) { return $false }
            if ($Value -match '^\.{1,2}([\\/]|$)') { return $true }
            # Rooted: a UNC or device path (\\server\share, //server/share, \\?\C:\).
            if ($Value -match '^[\\/]{2}') { return $false }
            # \x and /x are rooted on the CURRENT drive: they move with Set-Location D:\, so they count.
            if ($Value -match '^[\\/]') { return $true }
            # C:\x and C:/x are rooted. A Join-Path parent of bare C: is too (Join-Path C: x is C:\x).
            if ($Value -match '^[A-Za-z]:([\\/]|$)') { return ($Mode -ne 'Path' -and $Value.Length -eq 2) }
            # C:x is DRIVE-RELATIVE: it resolves against the current directory on drive C.
            if ($Value -match '^[A-Za-z]:') { return $true }
            # Rooted: a PowerShell drive (Env:, HKLM:, TestDrive:), or ~.
            if ($Value -match '^([A-Za-z][\w.-]+:|~)') { return $false }
            if ($Mode -eq 'Path') { return ($Value.Length -gt 0) }
            if ($Value -notmatch '[\\/]') { return $false }
            return $true
        }

        function Test-RelativePrefixText {
            # True when the static text that starts a built path ("lib\$name", '.\' + $name) puts it
            # in the current directory. A lone \ or C: may be completed by what follows (\\server,
            # C:\), so it is unknown and passes. The extension is checked by the caller.
            param([string]$Prefix, [string]$Mode)
            if ($Prefix -match '^([\\/]{1,2}|[A-Za-z]:)$') { return $false }
            $prefixMode = $Mode
            if ($Mode -eq 'Command') { $prefixMode = 'Module' }
            return (Test-RelativePathText -Value $Prefix -Mode $prefixMode)
        }

        function Get-UnwrappedElement {
            # Strips the syntactic wrappers that do not change a value, recursively: ( ), $( ) and
            # @( ) holding one statement, a single-element pipeline, a command expression, and a
            # cast ([string]x). Every place the resolver inspects an expression unwraps it first.
            param($Element)
            $current = $Element
            for ($i = 0; $i -lt 32; $i++) {
                $inner = $null
                if ($current -is [System.Management.Automation.Language.ParenExpressionAst]) { $inner = $current.Pipeline }
                elseif ($current -is [System.Management.Automation.Language.SubExpressionAst] -or
                    $current -is [System.Management.Automation.Language.ArrayExpressionAst]) {
                    $statements = @($current.SubExpression.Statements)
                    if ($statements.Count -eq 1) { $inner = $statements[0] }
                } elseif ($current -is [System.Management.Automation.Language.PipelineAst]) {
                    if ($current.PipelineElements.Count -eq 1) { $inner = $current.PipelineElements[0] }
                } elseif ($current -is [System.Management.Automation.Language.CommandExpressionAst]) { $inner = $current.Expression }
                elseif ($current -is [System.Management.Automation.Language.ConvertExpressionAst]) { $inner = $current.Child }
                if ($null -eq $inner) { return $current }
                $current = $inner
            }
            return $current
        }

        function Get-JoinPathChildElement {
            # Returns every element Join-Path joins onto its parent: -ChildPath, -AdditionalChildPath
            # and the positional arguments after the parent.
            param([System.Management.Automation.Language.CommandAst]$Command)
            $parentPath = Get-JoinPathParentElement -Command $Command
            $elements = $Command.CommandElements
            $i = 1
            while ($i -lt $elements.Count) {
                $element = $elements[$i]
                if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
                    $name = $element.ParameterName
                    $isChild = (Test-ParameterPrefix -Full 'ChildPath' -Name $name) -or (Test-ParameterPrefix -Full 'AdditionalChildPath' -Name $name)
                    if ($null -ne $element.Argument) {
                        if ($isChild) { $element.Argument }
                        $i++
                        continue
                    }
                    if ($isChild) {
                        if ($i + 1 -lt $elements.Count) { $elements[$i + 1] }
                        $i += 2
                        continue
                    }
                    if ('Resolve'.StartsWith($name, [System.StringComparison]::OrdinalIgnoreCase)) { $i++ } else { $i += 2 }
                    continue
                }
                if ($element -ne $parentPath) { $element }
                $i++
            }
        }

        function Test-KnownNonScriptElement {
            # True only when the path expression is STATICALLY known not to name a .ps1/.psm1/.psd1
            # ('tool.exe', "$tool.exe", $PWD, a variable whose every assignment is such a path).
            # Anything it cannot resolve (an unassigned variable, a command's output) is false: run
            # with . or & from a current-directory root, an unknown file is flagged, not passed.
            param($Element, [System.Management.Automation.Language.Ast]$Ast, [int]$Depth = 0)
            $Element = Get-UnwrappedElement -Element $Element
            if ($null -eq $Element -or $Depth -gt 8) { return $false }
            $next = $Depth + 1
            if ($Element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                return ($Element.Value -notmatch $script:scriptExtension)
            }
            if ($Element -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
                if ($Element.Value -match $script:scriptExtension) { return $false }
                $nested = @($Element.NestedExpressions)
                if ($nested.Count -eq 0) { return $true }
                $last = $nested[$nested.Count - 1]
                # "$tool.exe" ends in static text; "$base\$name" ends in what $name holds.
                if (-not $Element.Value.EndsWith($last.Extent.Text)) { return $true }
                return (Test-KnownNonScriptElement -Element $last -Ast $Ast -Depth $next)
            }
            if ($Element -is [System.Management.Automation.Language.BinaryExpressionAst] -and
                $Element.Operator -eq [System.Management.Automation.Language.TokenKind]::Plus) {
                return (Test-KnownNonScriptElement -Element $Element.Right -Ast $Ast -Depth $next)
            }
            if ($Element -is [System.Management.Automation.Language.VariableExpressionAst]) {
                if ($Element.VariablePath.UserPath -eq 'PWD') { return $true }
                $values = @(Get-AssignedValue -Ast $Ast -Name $Element.VariablePath.UserPath)
                if ($values.Count -eq 0) { return $false }
                foreach ($value in $values) {
                    if (-not (Test-KnownNonScriptElement -Element $value -Ast $Ast -Depth $next)) { return $false }
                }
                return $true
            }
            if ($Element -is [System.Management.Automation.Language.ArrayLiteralAst]) {
                foreach ($item in $Element.Elements) {
                    if (-not (Test-KnownNonScriptElement -Element $item -Ast $Ast -Depth $next)) { return $false }
                }
                return $true
            }
            if ($Element -is [System.Management.Automation.Language.CommandAst] -and (Get-BaseCommandName -Command $Element) -eq 'Join-Path') {
                $children = @(Get-JoinPathChildElement -Command $Element)
                if ($children.Count -eq 0) { return $false }
                foreach ($child in $children) {
                    if (-not (Test-KnownNonScriptElement -Element $child -Ast $Ast -Depth $next)) { return $false }
                }
                return $true
            }
            return $false
        }

        function Get-BaseCommandName {
            # The command name without a module qualifier (Microsoft.PowerShell.Core\Import-Module).
            # Comparisons on it are case-insensitive, so IMPORT-MODULE matches too.
            param([System.Management.Automation.Language.CommandAst]$Command)
            $name = $Command.GetCommandName()
            if ($null -eq $name) { return $null }
            if ($name -match '^[A-Za-z][\w.]*\\([A-Za-z][\w-]*)$') { return $Matches[1] }
            return $name
        }

        function Test-CurrentDirectoryPath {
            # The resolver: true when the path expression $Element, used as $Mode (see
            # Test-RelativePathText), is rooted in the current directory.
            param($Element, [System.Management.Automation.Language.Ast]$Ast, [string]$Mode, [int]$Depth = 0)
            $Element = Get-UnwrappedElement -Element $Element
            if ($null -eq $Element -or $Depth -gt 8) { return $false }
            $next = $Depth + 1
            if ($Element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                return (Test-RelativePathText -Value $Element.Value -Mode $Mode)
            }
            if ($Element -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
                if (Test-AnchoredElement -Element $Element) { return $false }
                # Judged by its static text: the extension in the trailing text, the root in the leading text.
                if ($Mode -eq 'Command' -and (Test-KnownNonScriptElement -Element $Element -Ast $Ast -Depth $next)) { return $false }
                $nested = @($Element.NestedExpressions)
                if ($nested.Count -eq 0) { return (Test-RelativePathText -Value $Element.Value -Mode $Mode) }
                if ($Element.Value -match '^\.{1,2}([\\/]|$)') { return $true }
                $index = $Element.Value.IndexOf($nested[0].Extent.Text)
                if ($index -lt 0) { return $false }
                if ($index -eq 0) {
                    # "$helper" is the variable itself; in "$base\Helper.psm1" it is the parent folder.
                    $leadMode = 'Path'
                    if ($Element.Value -eq $nested[0].Extent.Text) { $leadMode = $Mode }
                    return (Test-CurrentDirectoryPath -Element $nested[0] -Ast $Ast -Mode $leadMode -Depth $next)
                }
                return (Test-RelativePrefixText -Prefix $Element.Value.Substring(0, $index) -Mode $Mode)
            }
            if ($Element -is [System.Management.Automation.Language.BinaryExpressionAst] -and
                $Element.Operator -eq [System.Management.Automation.Language.TokenKind]::Plus) {
                # '.\' + 'Helper.psm1': judged by the leftmost operand (the root) and, run with
                # . or &, the rightmost operand (the extension).
                if ($Mode -eq 'Command' -and (Test-KnownNonScriptElement -Element $Element.Right -Ast $Ast -Depth $next)) { return $false }
                $left = Get-UnwrappedElement -Element $Element.Left
                while ($left -is [System.Management.Automation.Language.BinaryExpressionAst] -and
                    $left.Operator -eq [System.Management.Automation.Language.TokenKind]::Plus) { $left = Get-UnwrappedElement -Element $left.Left }
                if ($left -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                    return (Test-RelativePrefixText -Prefix $left.Value -Mode $Mode)
                }
                return (Test-CurrentDirectoryPath -Element $left -Ast $Ast -Mode 'Path' -Depth $next)
            }
            if ($Element -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $name = $Element.VariablePath.UserPath
                if ($script:anchorVariables -contains $name) { return $false }
                if ($name -eq 'PWD') { return $true }
                foreach ($value in @(Get-AssignedValue -Ast $Ast -Name $name)) {
                    if (Test-CurrentDirectoryPath -Element $value -Ast $Ast -Mode $Mode -Depth $next) { return $true }
                }
                return $false
            }
            if ($Element -is [System.Management.Automation.Language.HashtableAst]) {
                # A ModuleSpecification: @{ ModuleName = '.\x'; ModuleVersion = '1.0' }.
                if ($Mode -ne 'Module') { return $false }
                foreach ($pair in $Element.KeyValuePairs) {
                    if ($pair.Item1.Value -eq 'ModuleName' -and (Test-CurrentDirectoryPath -Element $pair.Item2 -Ast $Ast -Mode $Mode -Depth $next)) { return $true }
                }
                return $false
            }
            if ($Element -is [System.Management.Automation.Language.CommandAst]) {
                $command = Get-BaseCommandName -Command $Element
                if ($command -eq 'Join-Path') {
                    $parentPath = Get-JoinPathParentElement -Command $Element
                    # Run with . or &, a joined path statically known to name a non-script (an
                    # .exe) passes; a script child, or a child that cannot be resolved, is judged
                    # by the parent (conservative: an unknown file under $PWD is flagged).
                    if ($Mode -eq 'Command' -and (Test-KnownNonScriptElement -Element $Element -Ast $Ast -Depth $next)) { return $false }
                    return (Test-CurrentDirectoryPath -Element $parentPath -Ast $Ast -Mode 'Path' -Depth $next)
                }
                if ($script:locationCommands -contains $command) { return $true }
                # Any other command (Split-Path (Get-Location), ...): relative only when it is
                # fed $PWD or Get-Location and is not anchored.
                if (Test-AnchoredElement -Element $Element) { return $false }
                $locations = $script:locationCommands
                $found = $Element.Find({
                        param($node)
                        ($node -is [System.Management.Automation.Language.VariableExpressionAst] -and $node.VariablePath.UserPath -eq 'PWD') -or
                        ($node -is [System.Management.Automation.Language.CommandAst] -and $locations -contains (Get-BaseCommandName -Command $node))
                    }, $true)
                return ($null -ne $found)
            }
            if ($Element -is [System.Management.Automation.Language.MemberExpressionAst]) {
                # $PWD.Path, (Get-Location).Path: the object the member is read from.
                return (Test-CurrentDirectoryPath -Element $Element.Expression -Ast $Ast -Mode 'Path' -Depth $next)
            }
            # A list, or a $( ) / @( ) holding several statements: any item may be the path.
            $children = @()
            if ($Element -is [System.Management.Automation.Language.ArrayLiteralAst]) { $children = $Element.Elements }
            elseif ($Element -is [System.Management.Automation.Language.ArrayExpressionAst] -or
                $Element -is [System.Management.Automation.Language.SubExpressionAst]) { $children = $Element.SubExpression.Statements }
            foreach ($child in $children) {
                if (Test-CurrentDirectoryPath -Element $child -Ast $Ast -Mode $Mode -Depth $next) { return $true }
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
                        if ($isModule -and (Test-CurrentDirectoryPath -Element $element.Argument -Ast $Ast -Mode 'Module')) { return $true }
                        $i++
                        continue
                    }
                    if ($isModule) {
                        if ($i + 1 -lt $elements.Count -and (Test-CurrentDirectoryPath -Element $elements[$i + 1] -Ast $Ast -Mode 'Module')) { return $true }
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
                                    (Test-CurrentDirectoryPath -Element $pair.Item2 -Ast $Ast -Mode 'Module')) { return $true }
                            }
                        } elseif ($null -ne $splat -and (Test-CurrentDirectoryPath -Element $splat -Ast $Ast -Mode 'Module')) { return $true }
                    }
                    $i++
                    continue
                }
                if (-not $positionalSeen) {
                    $positionalSeen = $true
                    if (Test-CurrentDirectoryPath -Element $element -Ast $Ast -Mode 'Module') { return $true }
                }
                $i++
            }
            # '.\x' | Import-Module: the module name arrives as pipeline input.
            $pipeline = $Command.Parent
            if ($pipeline -is [System.Management.Automation.Language.PipelineAst]) {
                $index = $pipeline.PipelineElements.IndexOf($Command)
                if ($index -gt 0 -and (Test-CurrentDirectoryPath -Element $pipeline.PipelineElements[$index - 1] -Ast $Ast -Mode 'Module')) { return $true }
            }
            return $false
        }

        function Test-RelativeLoadSite {
            # True when a command is a loading site whose path is rooted in the current
            # directory. The first element of a command is what runs: the script or command
            # after . or &, or a script path typed as the command name (.\x.ps1 -Arg).
            param([System.Management.Automation.Language.CommandAst]$Command, [System.Management.Automation.Language.Ast]$Ast)
            if (Test-CurrentDirectoryPath -Element $Command.CommandElements[0] -Ast $Ast -Mode 'Command') { return $true }
            if ($script:importCommands -contains (Get-BaseCommandName -Command $Command)) { return (Test-RelativeImportCommand -Command $Command -Ast $Ast) }
            return $false
        }

        function Get-RelativeImportOffender {
            # Lists 'file:line: text' for every loading site under <Root>/Scripts and
            # <Root>/Modules that uses a working-directory-relative path, and
            # 'file:line: parse error ...' for unparsable files.
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
                $commands = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
                foreach ($command in $commands) {
                    if (Test-RelativeLoadSite -Command $command -Ast $ast) {
                        '{0}:{1}: {2}' -f $relative, $command.Extent.StartLineNumber, $command.Extent.Text
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
            @{ Name = 'Join-Path from a variable holding $PWD'; Code = "`$base = `$PWD`nImport-Module (Join-Path `$base 'Helper.psm1')" }
            @{ Name = 'Join-Path from a variable holding .'; Code = "`$base = '.'`nImport-Module (Join-Path `$base 'Helper.psm1')" }
            @{ Name = 'Join-Path from a variable holding Get-Location'; Code = "`$base = Get-Location`n. (Join-Path `$base 'Helper.ps1')" }
            @{ Name = 'Join-Path from a variable holding (Get-Location).Path'; Code = "`$base = (Get-Location).Path`nImport-Module (Join-Path -Path `$base -ChildPath 'Helper')" }
            @{ Name = 'an interpolated path from a variable holding $PWD'; Code = "`$base = `$PWD`n. `"`$base\Helper.ps1`"" }
            @{ Name = 'the call operator on a dot-slash script'; Code = '& .\Helper.ps1' }
            @{ Name = 'a dot-slash script run by name'; Code = '.\Helper.ps1 -Verbose' }
            @{ Name = 'a dot-source through a variable'; Code = "`$helper = '.\Helper.ps1'`n. `$helper" }
            @{ Name = 'the call operator through a Join-Path variable'; Code = "`$helper = Join-Path `$PWD 'Helper.ps1'`n& `$helper" }
            @{ Name = 'a dot-source of an unrooted script path'; Code = '. lib\Helper.ps1' }
            # C4: drive-relative and current-drive-root paths.
            @{ Name = 'a drive-relative module path (C:Helper)'; Code = 'Import-Module -Name ''C:Helper.psm1''' }
            @{ Name = 'a dot-source of a drive-relative script path'; Code = '. ''C:Helper.ps1''' }
            @{ Name = 'a current-drive-root module path (\Helper)'; Code = 'Import-Module ''\Helper.psm1''' }
            @{ Name = 'a dot-source of a current-drive-root script path'; Code = '. ''/Helper.ps1''' }
            @{ Name = 'Join-Path from a current-drive-root parent'; Code = 'Import-Module (Join-Path ''\'' ''Helper.psm1'')' }
            @{ Name = 'Join-Path from a drive-relative parent'; Code = 'Import-Module (Join-Path ''C:lib'' ''Helper.psm1'')' }
            # C5: every quote style at every point the resolver reads a string.
            @{ Name = 'the call operator on Join-Path $PWD with a double-quoted child'; Code = '& (Join-Path $PWD "Helper.ps1")' }
            @{ Name = 'the call operator on Join-Path $PWD with an interpolated child'; Code = '& (Join-Path $PWD "$name.ps1")' }
            @{ Name = 'a dot-source of Join-Path $PWD with a -ChildPath:value child'; Code = '. (Join-Path -Path $PWD -ChildPath:''Helper.ps1'')' }
            @{ Name = 'a double-quoted relative module path'; Code = 'Import-Module "lib\Helper"' }
            @{ Name = 'an interpolated module path with a relative leading folder'; Code = 'Import-Module "lib\$name"' }
            @{ Name = 'an interpolated -Name:value module path'; Code = 'Import-Module -Name:"lib\$name"' }
            @{ Name = 'an interpolated relative script path held in a variable'; Code = "`$helper = `"lib\`$name.ps1`"`n. `$helper" }
            @{ Name = 'Join-Path from an interpolated relative -Path'; Code = 'Import-Module (Join-Path -Path "lib\$sub" -ChildPath ''Helper.psm1'')' }
            @{ Name = 'an interpolated path from $(Get-Location)'; Code = 'Import-Module "$(Get-Location)\Helper.psm1"' }
            @{ Name = 'a double-quoted ModuleName'; Code = 'Import-Module -FullyQualifiedName @{ "ModuleName" = ".\Helper"; ModuleVersion = ''1.0'' }' }
            @{ Name = 'a double-quoted path piped to Import-Module'; Code = '".\Helper" | Import-Module' }
            # Self-critic: other cheap syntactic forms.
            @{ Name = 'a single-quoted here-string path'; Code = "Import-Module @'`n.\Helper`n'@" }
            @{ Name = 'a double-quoted here-string path'; Code = "Import-Module @`"`n.\Helper`n`"@" }
            @{ Name = 'an upper-case IMPORT-MODULE'; Code = 'IMPORT-MODULE .\Helper' }
            @{ Name = 'an upper-case IPMO'; Code = 'IPMO .\Helper' }
            @{ Name = 'an upper-case JOIN-PATH from $pwd'; Code = '. (JOIN-PATH $pwd ''Helper.ps1'')' }
            @{ Name = 'a module-qualified Import-Module'; Code = 'Microsoft.PowerShell.Core\Import-Module .\Helper' }
            @{ Name = 'a module-qualified Join-Path'; Code = '. (Microsoft.PowerShell.Management\Join-Path $PWD ''Helper.ps1'')' }
            @{ Name = 'the call operator on a quoted Import-Module'; Code = '& ''Import-Module'' .\Helper' }
            @{ Name = 'an abbreviated -N parameter'; Code = 'Import-Module -N .\Helper' }
            @{ Name = 'colon syntax -Name:.\Helper'; Code = 'Import-Module -Name:.\Helper' }
            @{ Name = 'a concatenated dot-slash module path'; Code = 'Import-Module (''.\'' + ''Helper.psm1'')' }
            @{ Name = 'a concatenated relative folder and variable'; Code = 'Import-Module (''lib\'' + $name)' }
            @{ Name = 'a dot-source of $PWD.Path concatenated with a script'; Code = '. ($PWD.Path + ''\Helper.ps1'')' }
            # C6: every syntactic wrapper, unwrapped recursively, at every point the resolver reads.
            @{ Name = 'the call operator on Join-Path $PWD with a parenthesized child'; Code = '& (Join-Path $PWD (''Helper.ps1''))' }
            @{ Name = 'a dot-source of Join-Path $PWD with a parenthesized child'; Code = '. (Join-Path $PWD (''Helper.ps1''))' }
            @{ Name = 'a Join-Path child in nested parentheses'; Code = '& (Join-Path $PWD ((''Helper.ps1'')))' }
            @{ Name = 'a cast Join-Path child'; Code = '. (Join-Path $PWD ([string]''Helper.ps1''))' }
            @{ Name = 'a $( ) Join-Path child'; Code = '. (Join-Path $PWD $(''Helper.ps1''))' }
            @{ Name = 'an @( ) Join-Path child'; Code = '. (Join-Path $PWD @(''Helper.ps1''))' }
            @{ Name = 'a parenthesized -ChildPath:value child'; Code = '. (Join-Path -Path $PWD -ChildPath:(''Helper.ps1''))' }
            @{ Name = 'a parenthesized Join-Path parent'; Code = '. (Join-Path ($PWD) ''Helper.ps1'')' }
            @{ Name = 'a cast Join-Path parent'; Code = '. (Join-Path ([string]$PWD) ''Helper.ps1'')' }
            @{ Name = 'a $( ) around the whole Join-Path'; Code = '. $(Join-Path $PWD ''Helper.ps1'')' }
            @{ Name = 'a cast around the whole Join-Path'; Code = '& ([string](Join-Path $PWD ''Helper.ps1''))' }
            @{ Name = 'a parenthesized dot-slash script'; Code = '. (''.\Helper.ps1'')' }
            @{ Name = 'a cast module path'; Code = 'Import-Module ([string]''.\Helper'')' }
            @{ Name = 'a $( ) module path'; Code = 'Import-Module $(''.\Helper'')' }
            @{ Name = 'an @( ) module path'; Code = 'Import-Module -Name @(''.\Helper'')' }
            @{ Name = 'a parenthesized concatenation operand'; Code = '. ((''.\'') + (''Helper.ps1''))' }
            @{ Name = 'a parenthesized variable assignment'; Code = "`$helper = ('.\Helper.ps1')`n. `$helper" }
            # C6: run with . or & from a current-directory root, an unresolvable file is flagged.
            @{ Name = 'the call operator on Join-Path $PWD with a variable child'; Code = '& (Join-Path $PWD $file)' }
            @{ Name = 'a dot-source of Join-Path . with a command-output child'; Code = '. (Join-Path ''.'' (Get-ChildItem).Name)' }
            @{ Name = 'Join-Path Get-Location with an interpolated variable child'; Code = '& (Join-Path (Get-Location) "$name")' }
            @{ Name = 'Join-Path (Get-Location).Path with a variable child'; Code = '. (Join-Path (Get-Location).Path $file)' }
            @{ Name = 'Join-Path from a traced Get-Location variable with a variable child'; Code = "`$base = Get-Location`n. (Join-Path `$base `$file)" }
            @{ Name = 'Join-Path from a drive-relative parent with a variable child'; Code = '. (Join-Path ''C:lib'' $file)' }
            @{ Name = 'Join-Path from an unrooted parent with a variable child'; Code = '& (Join-Path ''lib'' $file)' }
            @{ Name = 'a variable child assigned both an .exe and an unknown'; Code = "`$f = 'tool.exe'`n`$f = `$other`n& (Join-Path `$PWD `$f)" }
            @{ Name = 'an interpolated $PWD path ending in a variable'; Code = '. "$PWD\$name"' }
            @{ Name = 'a $PWD.Path concatenation ending in a variable'; Code = '& ($PWD.Path + $name)' }
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
            @{ Name = 'Test-Path on a dot-slash script'; Code = 'Test-Path -LiteralPath ''.\Helper.ps1''' }
            @{ Name = 'Copy-Item of a dot-slash script'; Code = "`$dest = 'C:\Temp'`nCopy-Item '.\Helper.ps1' `$dest" }
            @{ Name = 'Get-Content of a dot-slash script'; Code = 'Get-Content .\Helper.psm1' }
            @{ Name = 'a dot-slash script path assigned and never loaded'; Code = '$helper = ''.\Helper.ps1''' }
            @{ Name = 'a dot-slash script variable used only by Test-Path'; Code = "`$helper = '.\Helper.ps1'`nTest-Path `$helper" }
            @{ Name = 'a Join-Path from $PWD that is never loaded'; Code = "`$out = Join-Path `$PWD 'Report.ps1'`nSet-Content -Path `$out -Value 'x'" }
            @{ Name = 'Join-Path from a variable holding $PSScriptRoot'; Code = "`$base = `$PSScriptRoot`n. (Join-Path `$base 'Helper.ps1')" }
            @{ Name = 'Join-Path from an unassigned variable'; Code = 'Import-Module (Join-Path $env:ProgramFiles ''Helper'')' }
            @{ Name = 'a dot-source of an interpolated $PSScriptRoot path'; Code = '. $PSScriptRoot\Helper.ps1' }
            @{ Name = 'the call operator on a Join-Path $PSScriptRoot script'; Code = '& (Join-Path $PSScriptRoot ''Helper.ps1'')' }
            @{ Name = 'the call operator on a module-qualified command'; Code = '& ''Microsoft.PowerShell.Utility\Write-Output'' x' }
            @{ Name = 'the call operator on a script block'; Code = '& { Get-Item .\Helper.ps1 }' }
            @{ Name = 'a dot-slash native executable'; Code = '.\devcon.exe find =display' }
            @{ Name = 'the call operator on a Join-Path $PWD executable'; Code = '& (Join-Path $PWD ''tool.exe'') /q' }
            @{ Name = 'a UNC module path'; Code = 'Import-Module ''\\server\share\Helper.psm1''' }
            @{ Name = 'a dot-source of a UNC script path'; Code = '. ''\\server\share\Helper.ps1''' }
            @{ Name = 'a forward-slash absolute module path'; Code = 'Import-Module ''C:/Modules/Helper''' }
            @{ Name = 'Join-Path from a bare drive (C: joins to C:\)'; Code = 'Import-Module (Join-Path ''C:'' ''Helper.psm1'')' }
            @{ Name = 'a PowerShell-drive module path'; Code = 'Import-Module ''TestDrive:\Helper.psm1''' }
            @{ Name = 'an interpolated anchored module path'; Code = 'Import-Module "$PSScriptRoot\lib\$name"' }
            @{ Name = 'an interpolated module name held in a variable'; Code = "`$m = 'Pester'`nImport-Module `"`$m`"" }
            @{ Name = 'an interpolated bare module name'; Code = 'Import-Module "Helper-$suffix"' }
            @{ Name = 'an interpolated UNC module path'; Code = 'Import-Module "\\server\share\$name"' }
            @{ Name = 'the call operator on Join-Path $PWD with an interpolated .exe'; Code = '& (Join-Path $PWD "$tool.exe")' }
            @{ Name = 'an anchored concatenated module path'; Code = 'Import-Module ($PSScriptRoot + ''\Helper.psm1'')' }
            @{ Name = 'the call operator on a concatenated $PWD executable'; Code = '& ($PWD.Path + ''\tool.exe'')' }
            @{ Name = 'a double-quoted import by module name'; Code = 'Import-Module "Pester"' }
            # C6: wrappers around a non-script child, and unknown children under a rooted parent.
            @{ Name = 'the call operator on Join-Path $PWD with a parenthesized .exe'; Code = '& (Join-Path $PWD (''tool.exe''))' }
            @{ Name = 'the call operator on Join-Path $PWD with a cast .exe'; Code = '& (Join-Path $PWD ([string]$(''tool.exe'')))' }
            @{ Name = 'the call operator on Join-Path $PWD with a variable holding an .exe'; Code = "`$tool = 'tool.exe'`n& (Join-Path `$PWD `$tool)" }
            @{ Name = 'the call operator on Join-Path $PSScriptRoot with a variable child'; Code = '& (Join-Path $PSScriptRoot $file)' }
            @{ Name = 'a dot-source of Join-Path from a parenthesized $PSScriptRoot'; Code = '. (Join-Path ($PSScriptRoot) $file)' }
            @{ Name = 'the call operator on Join-Path from an unassigned variable with a variable child'; Code = '& (Join-Path $env:ProgramFiles $file)' }
            @{ Name = 'the call operator on Join-Path from a bare drive with a variable child'; Code = '& (Join-Path ''C:'' $file)' }
            @{ Name = 'Join-Path $PWD with a variable child, never loaded'; Code = '$out = Join-Path $PWD $file' }
            @{ Name = 'a parenthesized import by module name'; Code = 'Import-Module (''Pester'')' }
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
