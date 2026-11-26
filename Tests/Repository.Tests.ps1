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
    # This is an ALLOWLIST: a load site passes only when its path is one of the forms below.
    # Anything else, including anything the check cannot work out, fails.
    #
    # Load sites: dot-source (. <path>), the call operator (& <path>), running a script by path
    # (.\x.ps1 -Arg), and Import-Module / ipmo (-Name, -FullyQualifiedName, every positional
    # argument, a splatted hashtable or array, pipeline input). Command names match in any case
    # and with a module qualifier (My-Tools\Import-Module); parameters match by unambiguous
    # prefix, by alias and in -Name:value form. A parameter the check does not know to take a
    # value is read as a switch, so the argument after it is still checked (-vb .\x fails).
    # Every expression is first unwrapped from ( ), $( ), @( ), a cast and a one-element pipeline.
    #
    # A path PASSES when it is:
    #   (a) a constant bare module name: no \ or /, no :, no .ps1/.psm1/.psd1/.dll extension
    #       (Pester, Microsoft.PowerShell.Utility). For . and & and a script run by path, any
    #       constant command name with no \, / or : (Get-Item, Helper.ps1: these resolve through
    #       the command table, never the current directory), and Module\Verb-Noun.
    #   (b) anchored: its LEADING element is $PSScriptRoot or $PSCommandPath, or Split-Path of
    #       either or of $MyInvocation.MyCommand.Path. That is an expandable string whose first
    #       token is one ("$PSScriptRoot\x", not "lib\$PSScriptRoot\x"), Join-Path whose parent
    #       (-Path when named, else the first positional) is one, or a + chain whose first
    #       operand is one.
    #   (c) absolute: C:\x, C:/x, \\server\share\x, a PowerShell drive (Env:, TestDrive:\x),
    #       a provider path (FileSystem::), or ~. As a Join-Path parent a bare C: also passes.
    #   (d) rooted in the environment: $env:windir, $env:ProgramFiles, ...,
    #       [Environment]::GetFolderPath(...), [Environment]::SystemDirectory, $PSHOME, $HOME.
    #   (e) a variable whose EVERY assignment in the file is itself allowed. Scope qualifiers are
    #       ignored ($script:x, $global:x and $x are one name). A += or other compound write, a
    #       member or index write ($x.Name = ...), or a parameter makes the value unknown; a
    #       variable never assigned is unknown. A foreach loop variable takes each item of its
    #       collection, and $item.FullName passes when $item comes from Get-ChildItem or Get-Item
    #       of an allowed path (foreach, ForEach-Object over $_, or an assignment).
    #   (f) for . and & and a script run by path: a value statically known not to be a script,
    #       that is, its file extension is known and is not .ps1/.psm1/.psd1 (tool.exe, "$x.exe",
    #       Join-Path $PWD 'tool.exe'). The extension is read from the completed text, so
    #       'Helper.ps' + '1' is a script. A script block (& { ... }) is code, not a path.
    #   Constant parts are joined before judging: 'lib' + '/Helper.psm1' is lib/Helper.psm1,
    #   and "$a-$b" with $a = 'Helper' and $b = 'Tools' is the module name Helper-Tools.
    #
    # Everything else FAILS: .\x, ..\x, lib\x, C:x, \x, $PWD, Get-Location, a parameter, an
    # unassigned variable, a command's output, "lib\$name", "Helper-$unknown".
    #
    # SUPPRESS a load the check cannot prove safe with a comment that gives the reason, at the
    # end of the load's first line or alone on the line above it:
    #   # relative-import-ok: <reason>
    # An empty reason does not suppress.
    #
    # Not load sites, never checked: Test-Path, Copy-Item, Get-Content, Get-Module and other
    # non-loading commands; paths handed to a child process (pwsh -File, Start-Process); dynamic
    # code (Invoke-Expression, [scriptblock]::Create, code in strings); variables written by
    # Set-Variable, -OutVariable or [ref] (an = elsewhere in the file is all the check reads).
    # Manifests (.psd1) are not scanned: their RootModule, NestedModules and ScriptsToProcess
    # paths resolve against the manifest's folder. 'using module .\x.psm1' resolves against the
    # script's folder, so it is not a load site either. Scripts are parsed, never run.
    BeforeAll {
        $script:maxDepth = 8
        $script:anchorVariables = @('PSScriptRoot', 'PSCommandPath')
        $script:absoluteVariables = @('PSHOME', 'HOME')
        $script:scriptExtensions = @('ps1', 'psm1', 'psd1')
        $script:moduleFileExtension = '\.(ps1|psm1|psd1|dll)$'
        $script:importCommands = @('Import-Module', 'ipmo')
        $script:itemCommands = @('Get-ChildItem', 'gci', 'dir', 'ls', 'Get-Item', 'gi')
        $script:filterCommands = @('Where-Object', 'where', '?', 'Sort-Object', 'sort')
        $script:forEachCommands = @('ForEach-Object', 'foreach', '%')
        # Parameters that take a value. Any parameter not listed is read as a switch.
        $script:commonValueParameters = @('ErrorAction', 'WarningAction', 'InformationAction', 'ProgressAction', 'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable')
        $script:commonValueAliases = @{ ea = 'ErrorAction'; wa = 'WarningAction'; infa = 'InformationAction'; proga = 'ProgressAction'; ev = 'ErrorVariable'; wv = 'WarningVariable'; iv = 'InformationVariable'; ov = 'OutVariable'; ob = 'OutBuffer'; pv = 'PipelineVariable' }
        $script:importParameters = @('Name', 'FullyQualifiedName', 'Assembly', 'ModuleInfo', 'Prefix', 'Function', 'Cmdlet', 'Variable', 'Alias', 'ArgumentList', 'MinimumVersion', 'MaximumVersion', 'RequiredVersion', 'PSSession', 'CimSession', 'CimResourceUri', 'CimNamespace', 'Scope')
        $script:importAliases = @{ Args = 'ArgumentList'; Version = 'MinimumVersion' }
        $script:joinPathParameters = @('Path', 'ChildPath', 'AdditionalChildPath', 'Credential', 'Extension')
        $script:joinPathAliases = @{ PSPath = 'Path' }
        $script:splitPathParameters = @('Path', 'LiteralPath', 'Credential')
        $script:splitPathAliases = @{ PSPath = 'LiteralPath'; LP = 'LiteralPath' }
        # Split-Path switches that return something other than the containing folder.
        $script:splitPathNonRootSwitches = @('Leaf', 'LeafBase', 'Extension', 'Qualifier', 'NoQualifier', 'IsAbsolute')
        $script:itemParameters = @('Path', 'LiteralPath', 'Filter', 'Include', 'Exclude', 'Depth', 'Attributes', 'Credential', 'Stream')
        $script:itemAliases = @{ PSPath = 'LiteralPath'; LP = 'LiteralPath' }

        function Get-UnwrappedElement {
            # Strips the syntactic wrappers that do not change a value, recursively: ( ), $( ) and
            # @( ) holding one statement, a one-element pipeline, a command expression, and a cast.
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

        function Get-BaseCommandName {
            # The command name without a module qualifier (My-Tools\Import-Module). Comparisons on
            # it are case-insensitive, so IMPORT-MODULE matches too.
            param([System.Management.Automation.Language.CommandAst]$Command)
            $name = $Command.GetCommandName()
            if ($null -eq $name) { return $null }
            if ($name -match '^[A-Za-z][\w.-]*\\([A-Za-z][\w-]*)$') { return $Matches[1] }
            return $name
        }

        function Get-NormalizedVariableName {
            # $script:x, $global:x, $local:x, $private:x and $x are one name; $env:x stays itself.
            param([System.Management.Automation.Language.VariableExpressionAst]$Variable)
            return ($Variable.VariablePath.UserPath -replace '^(script|global|local|private):', '')
        }

        function Resolve-ParameterName {
            # The canonical name of a value-taking parameter written as $Name (exact, alias, or an
            # unambiguous prefix; on ambiguity the first listed wins), or $null for a switch.
            param([string]$Name, [string[]]$ValueParameters, [hashtable]$Aliases)
            $all = @($ValueParameters) + $script:commonValueParameters
            foreach ($candidate in $all) { if ($candidate -eq $Name) { return $candidate } }
            foreach ($key in @($Aliases.Keys) + @($script:commonValueAliases.Keys)) {
                if ($key -eq $Name) {
                    if ($Aliases.ContainsKey($key)) { return $Aliases[$key] }
                    return $script:commonValueAliases[$key]
                }
            }
            if ($Name.Length -eq 0) { return $null }
            foreach ($candidate in $all) {
                if ($candidate.StartsWith($Name, [System.StringComparison]::OrdinalIgnoreCase)) { return $candidate }
            }
            return $null
        }

        function Get-CommandBinding {
            # Binds a command's arguments: Named (canonical parameter -> argument), Positional (in
            # order) and Splatted (@var). Only $ValueParameters take a value; others are switches.
            param([System.Management.Automation.Language.CommandAst]$Command, [string[]]$ValueParameters, [hashtable]$Aliases)
            $named = @{}
            $positional = New-Object System.Collections.Generic.List[object]
            $splatted = New-Object System.Collections.Generic.List[object]
            $elements = $Command.CommandElements
            $i = 1
            while ($i -lt $elements.Count) {
                $element = $elements[$i]
                if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
                    $canonical = Resolve-ParameterName -Name $element.ParameterName -ValueParameters $ValueParameters -Aliases $Aliases
                    if ($null -ne $element.Argument) {
                        if ($canonical) { $named[$canonical] = $element.Argument }
                        $i++
                        continue
                    }
                    if ($canonical) {
                        if ($i + 1 -lt $elements.Count) { $named[$canonical] = $elements[$i + 1] }
                        $i += 2
                        continue
                    }
                    $i++
                    continue
                }
                if ($element -is [System.Management.Automation.Language.VariableExpressionAst] -and $element.Splatted) { $splatted.Add($element) }
                else { $positional.Add($element) }
                $i++
            }
            return [pscustomobject]@{ Named = $named; Positional = $positional.ToArray(); Splatted = $splatted.ToArray() }
        }

        function Get-JoinPathPart {
            # Join-Path's parent (-Path when named, else the first positional) and its last child.
            param([System.Management.Automation.Language.CommandAst]$Command)
            $binding = Get-CommandBinding -Command $Command -ValueParameters $script:joinPathParameters -Aliases $script:joinPathAliases
            $positional = @($binding.Positional)
            $parent = $binding.Named['Path']
            if ($null -eq $parent -and $positional.Count -gt 0) {
                $parent = $positional[0]
                $positional = @($positional | Select-Object -Skip 1)
            }
            $last = $binding.Named['AdditionalChildPath']
            if ($null -eq $last -and $positional.Count -gt 0) { $last = $positional[$positional.Count - 1] }
            if ($null -eq $last) { $last = $binding.Named['ChildPath'] }
            $unwrapped = Get-UnwrappedElement -Element $last
            if ($unwrapped -is [System.Management.Automation.Language.ArrayLiteralAst]) { $last = $unwrapped.Elements[$unwrapped.Elements.Count - 1] }
            return [pscustomobject]@{ Parent = $parent; LastChild = $last }
        }

        function Get-AssignedValue {
            # Every write to the variable named $Name anywhere in the file (scope-unaware): Kind is
            # Value (a plain =), ForEach (a foreach loop variable; Value is the collection) or
            # Unknown (+= and other compound writes, member and index writes, multi-target writes,
            # parameters).
            param([System.Management.Automation.Language.Ast]$Ast, [string]$Name)
            $nodes = $Ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.AssignmentStatementAst] -or
                    $node -is [System.Management.Automation.Language.ForEachStatementAst] -or
                    $node -is [System.Management.Automation.Language.ParameterAst]
                }, $true)
            foreach ($node in $nodes) {
                if ($node -is [System.Management.Automation.Language.ParameterAst]) {
                    if ((Get-NormalizedVariableName -Variable $node.Name) -eq $Name) { [pscustomobject]@{ Kind = 'Unknown'; Value = $null } }
                    continue
                }
                if ($node -is [System.Management.Automation.Language.ForEachStatementAst]) {
                    if ((Get-NormalizedVariableName -Variable $node.Variable) -eq $Name) { [pscustomobject]@{ Kind = 'ForEach'; Value = $node.Condition } }
                    continue
                }
                $left = $node.Left
                while ($left -is [System.Management.Automation.Language.AttributedExpressionAst]) { $left = $left.Child }
                if ($left -is [System.Management.Automation.Language.VariableExpressionAst]) {
                    if ((Get-NormalizedVariableName -Variable $left) -ne $Name) { continue }
                    if ($node.Operator -eq [System.Management.Automation.Language.TokenKind]::Equals) { [pscustomobject]@{ Kind = 'Value'; Value = $node.Right } }
                    else { [pscustomobject]@{ Kind = 'Unknown'; Value = $null } }
                    continue
                }
                # $x.Name = ..., $x[0] = ..., $a, $b = ...: any write that mentions the name.
                $mentioned = $left.Find({
                        param($v)
                        $v -is [System.Management.Automation.Language.VariableExpressionAst] -and (Get-NormalizedVariableName -Variable $v) -eq $Name
                    }, $true)
                if ($null -ne $mentioned) { [pscustomobject]@{ Kind = 'Unknown'; Value = $null } }
            }
        }

        function Get-ConcatenationPart {
            # The parts of a built string, in order: static text as [string] and the expressions
            # between them as ASTs. "lib\$x.ps1" is 'lib\', $x, '.ps1'; 'a' + $b is the operands.
            # Returns $null when the element is not a built string.
            param($Element)
            $Element = Get-UnwrappedElement -Element $Element
            $parts = New-Object System.Collections.Generic.List[object]
            if ($Element -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
                $value = $Element.Value
                $cursor = 0
                foreach ($nested in @($Element.NestedExpressions)) {
                    $index = $value.IndexOf($nested.Extent.Text, $cursor)
                    if ($index -lt 0) { return $null }
                    if ($index -gt $cursor) { $parts.Add($value.Substring($cursor, $index - $cursor)) }
                    $parts.Add($nested)
                    $cursor = $index + $nested.Extent.Text.Length
                }
                if ($cursor -lt $value.Length) { $parts.Add($value.Substring($cursor)) }
                return , $parts.ToArray()
            }
            if ($Element -is [System.Management.Automation.Language.BinaryExpressionAst] -and
                $Element.Operator -eq [System.Management.Automation.Language.TokenKind]::Plus) {
                $stack = New-Object System.Collections.Generic.List[object]
                $node = $Element
                while ($node -is [System.Management.Automation.Language.BinaryExpressionAst] -and
                    $node.Operator -eq [System.Management.Automation.Language.TokenKind]::Plus) {
                    $stack.Insert(0, $node.Right)
                    $node = Get-UnwrappedElement -Element $node.Left
                }
                $stack.Insert(0, $node)
                foreach ($operand in $stack) {
                    $operand = Get-UnwrappedElement -Element $operand
                    if ($operand -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $parts.Add($operand.Value) }
                    else { $parts.Add($operand) }
                }
                return , $parts.ToArray()
            }
            return $null
        }

        function Get-StaticValue {
            # Every value the expression can have, when all of them are known from the file
            # ('a', "$x-y" with $x assigned constants, 'Helper.ps' + '1'); $null otherwise.
            param($Element, [System.Management.Automation.Language.Ast]$Ast, [int]$Depth = 0)
            $Element = Get-UnwrappedElement -Element $Element
            if ($null -eq $Element -or $Depth -gt $script:maxDepth) { return $null }
            $next = $Depth + 1
            if ($Element -is [System.Management.Automation.Language.ConstantExpressionAst]) { return , @([string]$Element.Value) }
            if ($Element -is [System.Management.Automation.Language.BinaryExpressionAst]) {
                # A + chain is string concatenation only when it starts with a string.
                $first = Get-UnwrappedElement -Element $Element.Left
                while ($first -is [System.Management.Automation.Language.BinaryExpressionAst]) { $first = Get-UnwrappedElement -Element $first.Left }
                if ($first -is [System.Management.Automation.Language.ConstantExpressionAst] -and
                    $first -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { return $null }
            }
            $parts = Get-ConcatenationPart -Element $Element
            if ($null -ne $parts) {
                $values = @('')
                foreach ($part in $parts) {
                    if ($part -is [string]) { $partValues = @($part) }
                    else {
                        $partValues = Get-StaticValue -Element $part -Ast $Ast -Depth $next
                        if ($null -eq $partValues) { return $null }
                    }
                    $values = @(foreach ($v in $values) { foreach ($p in $partValues) { $v + $p } })
                    if ($values.Count -gt 32) { return $null }
                }
                return , $values
            }
            if ($Element -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $writes = @(Get-AssignedValue -Ast $Ast -Name (Get-NormalizedVariableName -Variable $Element))
                if ($writes.Count -eq 0) { return $null }
                $values = New-Object System.Collections.Generic.List[string]
                foreach ($write in $writes) {
                    if ($write.Kind -ne 'Value') { return $null }
                    $known = Get-StaticValue -Element $write.Value -Ast $Ast -Depth $next
                    if ($null -eq $known) { return $null }
                    foreach ($k in $known) { $values.Add($k) }
                }
                return , $values.ToArray()
            }
            return $null
        }

        function Get-FileExtension {
            # The extension of the last path component of $Text, or $null when it has none or when
            # the text does not reach back to a dot (an unknown part may still precede it).
            param([string]$Text)
            $leaf = ($Text -split '[\\/]')[-1]
            $dot = $leaf.LastIndexOf('.')
            if ($dot -lt 0) { return $null }
            return $leaf.Substring($dot + 1)
        }

        function Test-NonScriptText {
            # True when the text's file extension is known and is not a script's.
            param([string]$Text)
            $extension = Get-FileExtension -Text $Text
            return ($null -ne $extension -and $extension.Length -gt 0 -and $script:scriptExtensions -notcontains $extension)
        }

        function Test-KnownNonScript {
            # Rule (f): true when the value's extension is STATICALLY known and is not .ps1, .psm1 or
            # .psd1. The extension is read from the completed trailing text: in 'Helper.ps' + '1'
            # and "$PWD\Helper.$ext" ($ext = 'ps1') it is ps1.
            param($Element, [System.Management.Automation.Language.Ast]$Ast, [int]$Depth = 0)
            $Element = Get-UnwrappedElement -Element $Element
            if ($null -eq $Element -or $Depth -gt $script:maxDepth) { return $false }
            $next = $Depth + 1
            $values = Get-StaticValue -Element $Element -Ast $Ast -Depth $next
            if ($null -ne $values) {
                foreach ($value in $values) { if (-not (Test-NonScriptText -Text $value)) { return $false } }
                return $true
            }
            if ($Element -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $writes = @(Get-AssignedValue -Ast $Ast -Name (Get-NormalizedVariableName -Variable $Element))
                if ($writes.Count -eq 0) { return $false }
                foreach ($write in $writes) {
                    if ($write.Kind -ne 'Value' -or -not (Test-KnownNonScript -Element $write.Value -Ast $Ast -Depth $next)) { return $false }
                }
                return $true
            }
            if ($Element -is [System.Management.Automation.Language.CommandAst] -and (Get-BaseCommandName -Command $Element) -eq 'Join-Path') {
                # Join-Path -Extension replaces the child's extension, so the child no longer decides.
                $binding = Get-CommandBinding -Command $Element -ValueParameters $script:joinPathParameters -Aliases $script:joinPathAliases
                if ($binding.Named.ContainsKey('Extension')) { return $false }
                $last = (Get-JoinPathPart -Command $Element).LastChild
                if ($null -eq $last) { return $false }
                return (Test-KnownNonScript -Element $last -Ast $Ast -Depth $next)
            }
            $parts = Get-ConcatenationPart -Element $Element
            if ($null -eq $parts) { return $false }
            # Walk back from the end, joining every known part, until a part is unknown.
            $suffixes = @('')
            for ($i = $parts.Count - 1; $i -ge 0; $i--) {
                $part = $parts[$i]
                if ($part -is [string]) { $partValues = @($part) }
                else {
                    $partValues = Get-StaticValue -Element $part -Ast $Ast -Depth $next
                    if ($null -eq $partValues) {
                        # An unknown last part decides by itself ("$PWD\$tool", $tool = Join-Path ...).
                        if ($i -eq $parts.Count - 1) { return (Test-KnownNonScript -Element $part -Ast $Ast -Depth $next) }
                        break
                    }
                }
                $suffixes = @(foreach ($p in $partValues) { foreach ($s in $suffixes) { $p + $s } })
                if ($suffixes.Count -gt 32) { return $false }
            }
            foreach ($suffix in $suffixes) { if (-not (Test-NonScriptText -Text $suffix)) { return $false } }
            return $true
        }

        function Test-AbsoluteText {
            # Rule (c): text that starts at a fixed root, never the current directory.
            param([string]$Text)
            return ($Text -match '^([A-Za-z]:[\\/]|[\\/]{2}|[A-Za-z][\w.-]+:|[\w.\\-]+::|~([\\/]|$))')
        }

        function Test-RootItemSource {
            # True when the element yields file items from an allowed root: Get-ChildItem or Get-Item
            # of an allowed path, optionally piped through Where-Object or Sort-Object, a variable
            # holding one, or $_ inside ForEach-Object fed by one.
            param($Element, [System.Management.Automation.Language.Ast]$Ast, [int]$Depth = 0)
            $Element = Get-UnwrappedElement -Element $Element
            if ($null -eq $Element -or $Depth -gt $script:maxDepth) { return $false }
            $next = $Depth + 1
            if ($Element -is [System.Management.Automation.Language.PipelineAst]) {
                return (Test-PipelinePrefixItemSource -Pipeline $Element -Count $Element.PipelineElements.Count -Ast $Ast -Depth $next)
            }
            if ($Element -is [System.Management.Automation.Language.CommandAst]) {
                if ($script:itemCommands -notcontains (Get-BaseCommandName -Command $Element)) { return $false }
                $binding = Get-CommandBinding -Command $Element -ValueParameters $script:itemParameters -Aliases $script:itemAliases
                $path = $binding.Named['Path']
                if ($null -eq $path) { $path = $binding.Named['LiteralPath'] }
                if ($null -eq $path -and @($binding.Positional).Count -gt 0) { $path = @($binding.Positional)[0] }
                if ($null -eq $path) { return $false }
                return (Test-RootElement -Element $path -Ast $Ast -Depth $next)
            }
            if ($Element -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $name = Get-NormalizedVariableName -Variable $Element
                if ($name -eq '_' -or $name -eq 'PSItem') {
                    # $_ in ForEach-Object { }: the items piped into that ForEach-Object.
                    $block = $Element.Parent
                    while ($null -ne $block -and $block -isnot [System.Management.Automation.Language.ScriptBlockAst]) { $block = $block.Parent }
                    if ($null -eq $block -or $block.Parent -isnot [System.Management.Automation.Language.ScriptBlockExpressionAst]) { return $false }
                    $command = $block.Parent.Parent
                    if ($command -isnot [System.Management.Automation.Language.CommandAst] -or
                        $script:forEachCommands -notcontains (Get-BaseCommandName -Command $command)) { return $false }
                    $pipeline = $command.Parent
                    if ($pipeline -isnot [System.Management.Automation.Language.PipelineAst]) { return $false }
                    $index = $pipeline.PipelineElements.IndexOf($command)
                    if ($index -lt 1) { return $false }
                    return (Test-PipelinePrefixItemSource -Pipeline $pipeline -Count $index -Ast $Ast -Depth $next)
                }
                $writes = @(Get-AssignedValue -Ast $Ast -Name $name)
                if ($writes.Count -eq 0) { return $false }
                foreach ($write in $writes) {
                    if ($write.Kind -eq 'Unknown' -or -not (Test-RootItemSource -Element $write.Value -Ast $Ast -Depth $next)) { return $false }
                }
                return $true
            }
            # @($private + $public), @($a, $b): every operand must be an item source.
            $operands = $null
            if ($Element -is [System.Management.Automation.Language.BinaryExpressionAst] -and
                $Element.Operator -eq [System.Management.Automation.Language.TokenKind]::Plus) { $operands = @($Element.Left, $Element.Right) }
            elseif ($Element -is [System.Management.Automation.Language.ArrayLiteralAst]) { $operands = $Element.Elements }
            if ($null -ne $operands) {
                foreach ($operand in $operands) {
                    if (-not (Test-RootItemSource -Element $operand -Ast $Ast -Depth $next)) { return $false }
                }
                return $true
            }
            return $false
        }

        function Test-PipelinePrefixItemSource {
            # True when the first $Count elements of $Pipeline are an item source followed only by
            # filters (Where-Object, Sort-Object).
            param([System.Management.Automation.Language.PipelineAst]$Pipeline, [int]$Count, [System.Management.Automation.Language.Ast]$Ast, [int]$Depth)
            $elements = $Pipeline.PipelineElements
            if ($Count -lt 1) { return $false }
            for ($i = 1; $i -lt $Count; $i++) {
                if ($elements[$i] -isnot [System.Management.Automation.Language.CommandAst] -or
                    $script:filterCommands -notcontains (Get-BaseCommandName -Command $elements[$i])) { return $false }
            }
            return (Test-RootItemSource -Element $elements[0] -Ast $Ast -Depth $Depth)
        }

        function Test-RootElement {
            # Rules (b), (c), (d): true when the value STARTS at an anchored, absolute or environment
            # root. Only the leading element counts: "$PSScriptRoot\x" passes, "lib\$PSScriptRoot\x"
            # does not. -AllowBareDrive accepts C: (a Join-Path parent: Join-Path C: x is C:\x).
            param($Element, [System.Management.Automation.Language.Ast]$Ast, [int]$Depth = 0, [switch]$AllowBareDrive)
            $Element = Get-UnwrappedElement -Element $Element
            if ($null -eq $Element -or $Depth -gt $script:maxDepth) { return $false }
            $next = $Depth + 1
            $values = Get-StaticValue -Element $Element -Ast $Ast -Depth $next
            if ($null -ne $values) {
                foreach ($value in $values) {
                    if (-not ((Test-AbsoluteText -Text $value) -or ($AllowBareDrive -and $value -match '^[A-Za-z]:$'))) { return $false }
                }
                return $true
            }
            if ($Element -is [System.Management.Automation.Language.VariableExpressionAst]) {
                if ($Element.VariablePath.DriveName -eq 'env') { return $true }
                $name = Get-NormalizedVariableName -Variable $Element
                if ($script:anchorVariables -contains $name -or $script:absoluteVariables -contains $name) { return $true }
                $writes = @(Get-AssignedValue -Ast $Ast -Name $name)
                if ($writes.Count -eq 0) { return $false }
                foreach ($write in $writes) {
                    if ($write.Kind -eq 'Unknown' -or -not (Test-RootElement -Element $write.Value -Ast $Ast -Depth $next -AllowBareDrive:$AllowBareDrive)) { return $false }
                }
                return $true
            }
            $parts = Get-ConcatenationPart -Element $Element
            if ($null -ne $parts) {
                if ($parts.Count -eq 0) { return $false }
                $first = $parts[0]
                if ($first -is [string]) { return (Test-AbsoluteText -Text $first) }
                return (Test-RootElement -Element $first -Ast $Ast -Depth $next)
            }
            if ($Element -is [System.Management.Automation.Language.CommandAst]) {
                $command = Get-BaseCommandName -Command $Element
                if ($command -eq 'Join-Path') {
                    return (Test-RootElement -Element (Get-JoinPathPart -Command $Element).Parent -Ast $Ast -Depth $next -AllowBareDrive)
                }
                if ($command -eq 'Split-Path') {
                    foreach ($parameter in @($Element.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] })) {
                        foreach ($switch in $script:splitPathNonRootSwitches) {
                            if ($switch.StartsWith($parameter.ParameterName, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
                        }
                    }
                    $binding = Get-CommandBinding -Command $Element -ValueParameters $script:splitPathParameters -Aliases $script:splitPathAliases
                    $path = $binding.Named['Path']
                    if ($null -eq $path) { $path = $binding.Named['LiteralPath'] }
                    if ($null -eq $path -and @($binding.Positional).Count -gt 0) { $path = @($binding.Positional)[0] }
                    return (Test-RootElement -Element $path -Ast $Ast -Depth $next)
                }
                return $false
            }
            if ($Element -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
                # [Environment]::GetFolderPath(...)
                return ($Element.Static -and $Element.Expression -is [System.Management.Automation.Language.TypeExpressionAst] -and
                    @('Environment', 'System.Environment') -contains $Element.Expression.TypeName.FullName -and
                    $Element.Member.Extent.Text -eq 'GetFolderPath')
            }
            if ($Element -is [System.Management.Automation.Language.MemberExpressionAst]) {
                $member = $Element.Member.Extent.Text
                if ($Element.Static) {
                    # [Environment]::SystemDirectory
                    return ($Element.Expression -is [System.Management.Automation.Language.TypeExpressionAst] -and
                        @('Environment', 'System.Environment') -contains $Element.Expression.TypeName.FullName -and
                        $member -eq 'SystemDirectory')
                }
                $base = Get-UnwrappedElement -Element $Element.Expression
                # $MyInvocation.MyCommand.Path / .Definition, $MyInvocation.PSScriptRoot / .PSCommandPath.
                if ($base -is [System.Management.Automation.Language.VariableExpressionAst] -and $base.VariablePath.UserPath -eq 'MyInvocation' -and
                    @('PSScriptRoot', 'PSCommandPath') -contains $member) { return $true }
                if ($base -is [System.Management.Automation.Language.MemberExpressionAst] -and $base.Member.Extent.Text -eq 'MyCommand' -and
                    @('Path', 'Definition') -contains $member) {
                    $invocation = Get-UnwrappedElement -Element $base.Expression
                    return ($invocation -is [System.Management.Automation.Language.VariableExpressionAst] -and $invocation.VariablePath.UserPath -eq 'MyInvocation')
                }
                # $file.FullName where $file is an item from an allowed root.
                if (@('FullName', 'DirectoryName', 'PSPath') -contains $member) {
                    return (Test-RootItemSource -Element $base -Ast $Ast -Depth $next)
                }
                return $false
            }
            if ($Element -is [System.Management.Automation.Language.ArrayLiteralAst]) {
                foreach ($item in $Element.Elements) {
                    if (-not (Test-RootElement -Element $item -Ast $Ast -Depth $next -AllowBareDrive:$AllowBareDrive)) { return $false }
                }
                return $true
            }
            return $false
        }

        function Test-AllowedConstant {
            # Rules (a), (c), (f) for a fully known value. $Mode is Module (Import-Module) or
            # Command (. and & and a script run by path).
            param([string]$Value, [string]$Mode)
            if (Test-AbsoluteText -Text $Value) { return $true }
            if ($Mode -eq 'Module') {
                return ($Value -match '^[A-Za-z0-9_][\w.-]*$' -and $Value -notmatch $script:moduleFileExtension)
            }
            if ($Value -match '^[^\\/:]+$' -and $Value -notmatch '^\.+$') { return $true }
            if ($Value -match '^[A-Za-z][\w.-]*\\[A-Za-z]\w*-\w+$') { return $true }
            return (Test-NonScriptText -Text $Value)
        }

        function Test-AllowedPath {
            # The allowlist: true only when the path expression, used as $Mode, is one of the
            # forms in the header. Anything else, including anything unknown, is false.
            param($Element, [System.Management.Automation.Language.Ast]$Ast, [string]$Mode, [int]$Depth = 0)
            $Element = Get-UnwrappedElement -Element $Element
            if ($null -eq $Element -or $Depth -gt $script:maxDepth) { return $false }
            $next = $Depth + 1
            $values = Get-StaticValue -Element $Element -Ast $Ast -Depth $next
            if ($null -ne $values) {
                foreach ($value in $values) { if (-not (Test-AllowedConstant -Value $value -Mode $Mode)) { return $false } }
                return $true
            }
            if ($Mode -eq 'Command') {
                if ($Element -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { return $true }
                if (Test-KnownNonScript -Element $Element -Ast $Ast -Depth $next) { return $true }
            }
            if (Test-RootElement -Element $Element -Ast $Ast -Depth $next) { return $true }
            if ($Element -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $writes = @(Get-AssignedValue -Ast $Ast -Name (Get-NormalizedVariableName -Variable $Element))
                if ($writes.Count -eq 0) { return $false }
                foreach ($write in $writes) {
                    if ($write.Kind -eq 'Unknown' -or -not (Test-AllowedPath -Element $write.Value -Ast $Ast -Mode $Mode -Depth $next)) { return $false }
                }
                return $true
            }
            if ($Element -is [System.Management.Automation.Language.HashtableAst]) {
                # A ModuleSpecification: @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }.
                if ($Mode -ne 'Module') { return $false }
                $moduleName = @($Element.KeyValuePairs | Where-Object { [string]$_.Item1.Value -eq 'ModuleName' })
                if ($moduleName.Count -eq 0) { return $false }
                foreach ($pair in $moduleName) {
                    if (-not (Test-AllowedPath -Element $pair.Item2 -Ast $Ast -Mode $Mode -Depth $next)) { return $false }
                }
                return $true
            }
            $items = $null
            if ($Element -is [System.Management.Automation.Language.ArrayLiteralAst]) { $items = $Element.Elements }
            elseif ($Element -is [System.Management.Automation.Language.ArrayExpressionAst] -or
                $Element -is [System.Management.Automation.Language.SubExpressionAst]) { $items = $Element.SubExpression.Statements }
            if ($null -ne $items) {
                foreach ($item in $items) {
                    if (-not (Test-AllowedPath -Element $item -Ast $Ast -Mode $Mode -Depth $next)) { return $false }
                }
                return $true
            }
            return $false
        }

        function Get-SplatSource {
            # The hashtables and arrays a splatted variable can hold, following variable-to-variable
            # copies ($copy = $original). $null when any write is unknown or not a literal.
            param([string]$Name, [System.Management.Automation.Language.Ast]$Ast, [int]$Depth = 0)
            if ($Depth -gt $script:maxDepth) { return $null }
            $writes = @(Get-AssignedValue -Ast $Ast -Name $Name)
            if ($writes.Count -eq 0) { return $null }
            $sources = New-Object System.Collections.Generic.List[object]
            foreach ($write in $writes) {
                if ($write.Kind -ne 'Value') { return $null }
                $value = Get-UnwrappedElement -Element $write.Value
                if ($value -is [System.Management.Automation.Language.VariableExpressionAst]) {
                    $inner = Get-SplatSource -Name (Get-NormalizedVariableName -Variable $value) -Ast $Ast -Depth ($Depth + 1)
                    if ($null -eq $inner) { return $null }
                    foreach ($source in $inner) { $sources.Add($source) }
                    continue
                }
                $sources.Add($value)
            }
            return , $sources.ToArray()
        }

        function Test-AllowedImport {
            # True when every module an Import-Module call can load is allowed: -Name,
            # -FullyQualifiedName, every positional argument, splatted values, and pipeline input.
            param([System.Management.Automation.Language.CommandAst]$Command, [System.Management.Automation.Language.Ast]$Ast)
            $binding = Get-CommandBinding -Command $Command -ValueParameters $script:importParameters -Aliases $script:importAliases
            $candidates = New-Object System.Collections.Generic.List[object]
            foreach ($key in @('Name', 'FullyQualifiedName')) { if ($binding.Named.ContainsKey($key)) { $candidates.Add($binding.Named[$key]) } }
            foreach ($element in @($binding.Positional)) { $candidates.Add($element) }
            foreach ($splat in @($binding.Splatted)) {
                $sources = Get-SplatSource -Name (Get-NormalizedVariableName -Variable $splat) -Ast $Ast
                if ($null -eq $sources) { return $false }
                foreach ($source in $sources) {
                    if ($source -is [System.Management.Automation.Language.HashtableAst]) {
                        foreach ($pair in $source.KeyValuePairs) {
                            $key = Resolve-ParameterName -Name ([string]$pair.Item1.Value) -ValueParameters $script:importParameters -Aliases $script:importAliases
                            if ($key -eq 'Name' -or $key -eq 'FullyQualifiedName') { $candidates.Add($pair.Item2) }
                        }
                    } else { $candidates.Add($source) }
                }
            }
            # '.\x' | Import-Module: the module name arrives as pipeline input.
            $pipeline = $Command.Parent
            if ($pipeline -is [System.Management.Automation.Language.PipelineAst]) {
                $index = $pipeline.PipelineElements.IndexOf($Command)
                if ($index -gt 0) { $candidates.Add($pipeline.PipelineElements[$index - 1]) }
            }
            foreach ($candidate in $candidates) {
                if (-not (Test-AllowedPath -Element $candidate -Ast $Ast -Mode 'Module')) { return $false }
            }
            return $true
        }

        function Test-AllowedLoadSite {
            # True when a command is not a load site or loads only allowed paths. The first element
            # of a command is what runs: a command name, the script or command after . or &, or a
            # script path typed as the command name (.\x.ps1 -Arg).
            param([System.Management.Automation.Language.CommandAst]$Command, [System.Management.Automation.Language.Ast]$Ast)
            if (-not (Test-AllowedPath -Element $Command.CommandElements[0] -Ast $Ast -Mode 'Command')) { return $false }
            if ($script:importCommands -contains (Get-BaseCommandName -Command $Command)) { return (Test-AllowedImport -Command $Command -Ast $Ast) }
            return $true
        }

        function Get-SuppressedLine {
            # Line numbers a '# relative-import-ok: <reason>' comment exempts: its own line when it
            # follows code there, else the next line. A comment with no reason exempts nothing.
            param([System.Management.Automation.Language.Token[]]$Tokens, [string[]]$Lines)
            foreach ($token in $Tokens) {
                if ($token.Kind -ne [System.Management.Automation.Language.TokenKind]::Comment) { continue }
                if ($token.Text -notmatch '^#\s*relative-import-ok:\s*\S') { continue }
                $line = $token.Extent.StartLineNumber
                $before = $Lines[$line - 1].Substring(0, $token.Extent.StartColumnNumber - 1)
                if ($before.Trim().Length -gt 0) { $line } else { $line + 1 }
            }
        }

        function Get-RelativeImportOffender {
            # Lists 'file:line: text' for every load site under <Root>/Scripts and <Root>/Modules
            # whose path is not allowed and not suppressed, and 'file:line: parse error ...' for
            # unparsable files.
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
                $suppressed = @(Get-SuppressedLine -Tokens $tokens -Lines ($ast.Extent.Text -split "`r?`n"))
                $commands = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
                foreach ($command in $commands) {
                    if ($suppressed -contains $command.Extent.StartLineNumber) { continue }
                    if (-not (Test-AllowedLoadSite -Command $command -Ast $ast)) {
                        '{0}:{1}: {2}' -f $relative, $command.Extent.StartLineNumber, $command.Extent.Text
                    }
                }
            }
        }

        function Invoke-FixtureScan {
            # Writes $Code to Scripts/Case.ps1 under a fresh root and returns the offenders.
            param([string]$Code)
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $root 'Scripts') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'Scripts/Case.ps1') -Value $Code -Encoding UTF8
            return @(Get-RelativeImportOffender -Root $root)
        }
    }

    It 'no code under Scripts/ or Modules/ loads a script or module from a .\ or ./ path' {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $offenders = @(Get-RelativeImportOffender -Root $repoRoot | Select-Object -Unique)
        $offenders | Should -BeNullOrEmpty -Because ('these load a path the allowlist cannot prove is anchored (anchor them to $PSScriptRoot, or add a "# relative-import-ok: <reason>" comment), or do not parse: ' + ($offenders -join '; '))
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
            @{ Name = 'a drive-relative extensionless module path'; Code = 'Import-Module -Name ''C:Helper''' }
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
            @{ Name = 'a single-quoted here-string path'; Code = "Import-Module @'`n.\Helper`n'@"; Line = 1 }
            @{ Name = 'a double-quoted here-string path'; Code = "Import-Module @`"`n.\Helper`n`"@"; Line = 1 }
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
            # Moved from the "does not flag" table by the allowlist: an unknown part is not safe.
            @{ Name = 'an interpolated module name with an unknown part'; Code = 'Import-Module "Helper-$suffix"' }
            @{ Name = 'an import from a parameter'; Code = "param(`$ModulePath)`nImport-Module `$ModulePath" }
            @{ Name = 'a dot-source of an unassigned variable'; Code = '. $helper' }
            @{ Name = 'a bare module file name (Import-Module resolves it against the current directory)'; Code = 'Import-Module Helper.psm1' }
            # Round 5 findings, one or more fixtures each.
            @{ Name = '4702618520: a hyphenated module qualifier'; Code = 'My-Tools\Import-Module .\Helper' }
            @{ Name = '4702618520: a quoted hyphenated module qualifier'; Code = '& ''My-Tools\Import-Module'' .\Helper' }
            @{ Name = '4702618562: $PSScriptRoot after $PWD in an interpolated path'; Code = 'Import-Module "$PWD\$PSScriptRoot\Helper.psm1"' }
            @{ Name = '4702618562: $PSScriptRoot after a relative folder in an interpolated path'; Code = 'Import-Module "lib\$PSScriptRoot\Helper.psm1"' }
            @{ Name = '4702662191: a $script:-scoped assignment read unqualified'; Code = "`$script:helper = '.\Helper.psm1'`nImport-Module `$helper" }
            @{ Name = '4702662191: a $global:-scoped assignment read $script:-qualified'; Code = "`$global:helper = '.\Helper.psm1'`nImport-Module `$script:helper" }
            @{ Name = '4702662238: a Join-Path $PWD child concatenated into .ps1'; Code = '& (Join-Path $PWD (''Helper.ps'' + ''1''))' }
            @{ Name = '4702662238: a $PWD.Path concatenation completed into .ps1'; Code = '& ($PWD.Path + ''\Helper.ps'' + ''1'')' }
            @{ Name = '4702662238: an interpolated $PWD path whose extension is a variable'; Code = "`$ext = 'ps1'`n. `"`$PWD\Helper.`$ext`"" }
            @{ Name = '4702662310: a splat through a variable alias'; Code = "`$original = @{ Name = '.\Helper.psm1' }`n`$copy = `$original`nImport-Module @copy" }
            @{ Name = '4702662310: a splat of a hashtable changed by a member write'; Code = "`$importArgs = @{ Force = `$true }`n`$importArgs.Name = '.\Helper.psm1'`nImport-Module @importArgs" }
            @{ Name = '4702665676: a += that completes a .ps1 child'; Code = "`$file = 'Helper.ps'`n`$file += '1'`n& (Join-Path `$PWD `$file)" }
            @{ Name = '4702665687: $PSScriptRoot inside a relative file name'; Code = 'Import-Module "./Helpers/$(Split-Path -Leaf $PSScriptRoot).psm1"' }
            @{ Name = '4702665687: Split-Path -Leaf of $PSScriptRoot as a Join-Path parent'; Code = 'Import-Module (Join-Path (Split-Path -Leaf $PSScriptRoot) ''Helper.psm1'')' }
            @{ Name = '4702665698: a dot-slash .ps1 split across a concatenation'; Code = '& (''./Helper.ps'' + ''1'')' }
            @{ Name = '4702665705: a relative module path split after the folder'; Code = 'Import-Module (''lib'' + ''/Helper.psm1'')' }
            @{ Name = '4702665716: the -vb switch alias before the path'; Code = 'Import-Module -vb ./Helper.psm1' }
            @{ Name = '4702665716: the -db switch alias before the path'; Code = 'Import-Module -db ./Helper.psm1' }
            @{ Name = '4702665716: an unknown switch before the path'; Code = 'Import-Module -SomeNewSwitch ./Helper.psm1' }
            @{ Name = 'Join-Path -Extension turning an .exe child into a script'; Code = '& (Join-Path $PWD ''tool.exe'' -Extension ''.ps1'')' }
            @{ Name = 'a suppression comment with no reason'; Code = "# relative-import-ok:`nImport-Module .\Helper.psm1" }
            @{ Name = 'a suppression comment two lines above'; Code = "# relative-import-ok: tested from the repo root only`n`nImport-Module .\Helper.psm1" }
            @{ Name = 'a foreach variable over Get-ChildItem of the current directory'; Code = "foreach (`$file in Get-ChildItem -Filter *.ps1) {`n. `$file.FullName`n}"; Line = 2 }
            @{ Name = 'a foreach over an anchored and a relative Get-ChildItem joined with +'; Code = "`$a = @(Get-ChildItem -Path `$PSScriptRoot)`n`$b = @(Get-ChildItem -Path 'Public')`nforeach (`$file in @(`$a + `$b)) {`n. `$file.FullName`n}"; Line = 4 }
            @{ Name = 'ForEach-Object over Get-ChildItem of a relative folder'; Code = 'Get-ChildItem lib -Filter *.ps1 | ForEach-Object { . $_.FullName }' }
        ) {
            param($Name, $Code, $Line)
            $offenders = Invoke-FixtureScan -Code $Code
            if (-not $Line) { $Line = @($Code -split "`n").Count }
            @($offenders | Where-Object { $_ -match ': parse error: ' }) | Should -BeNullOrEmpty -Because "$Name must parse, so the load site itself is what is reported"
            @($offenders | Where-Object { $_ -match "^Scripts[\\/]Case\.ps1:${Line}: " }).Count | Should -BeGreaterThan 0 -Because "$Name loads relative to the current directory on line $Line (reported: $($offenders -join '; '))"
        }

        It 'reports a file that does not parse, since it could hide a load' {
            $offenders = Invoke-FixtureScan -Code "function Broken {`n    if ("
            @($offenders | Where-Object { $_ -match '^Scripts[\\/]Case\.ps1:\d+: parse error: ' }).Count | Should -Be 1
        }

        It 'does not flag <Name>' -TestCases @(
            @{ Name = 'Join-Path $PSScriptRoot with a dot-slash child'; Code = 'Import-Module (Join-Path $PSScriptRoot ''.\Helper.psm1'')' }
            @{ Name = 'Join-Path -Path $PSScriptRoot -ChildPath'; Code = 'Import-Module (Join-Path -ChildPath ''.\Helper.psm1'' -Path $PSScriptRoot)' }
            @{ Name = 'Join-Path from $PSCommandPath''s folder'; Code = 'Import-Module (Join-Path (Split-Path $PSCommandPath) ''.\Helper.psm1'')' }
            @{ Name = 'Join-Path from Split-Path -Parent of $MyInvocation.MyCommand.Path'; Code = '. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) ''Helper.ps1'')' }
            @{ Name = 'an interpolated $PSScriptRoot path'; Code = 'Import-Module "$PSScriptRoot\Helper.psm1"' }
            @{ Name = 'using module with a relative path'; Code = 'using module .\Helper.psm1' }
            @{ Name = 'an import by module name'; Code = 'Import-Module Helper' }
            @{ Name = 'Import-Module Pester'; Code = 'Import-Module Pester' }
            @{ Name = 'Import-Module MsiTools -Force'; Code = 'Import-Module MsiTools -Force' }
            @{ Name = 'a dotted module name'; Code = 'Import-Module -Name Microsoft.PowerShell.Utility' }
            @{ Name = 'a ModuleSpecification by name'; Code = 'Import-Module -FullyQualifiedName @{ ModuleName = ''Pester''; ModuleVersion = ''5.0'' }' }
            @{ Name = 'an extensionless Join-Path $PSScriptRoot import'; Code = 'Import-Module (Join-Path $PSScriptRoot ''Helper'')' }
            @{ Name = 'an extensionless interpolated $PSScriptRoot import'; Code = 'Import-Module "$PSScriptRoot\Helper"' }
            @{ Name = 'an absolute module path'; Code = 'Import-Module -Name ''C:\Modules\Helper''' }
            @{ Name = 'Get-Module -ListAvailable on a relative path'; Code = 'Get-Module -ListAvailable -Name .\Helper' }
            @{ Name = 'a relative variable that is never imported'; Code = "`$helper = '.\Helper'`nGet-Item `$helper`nImport-Module Pester" }
            @{ Name = 'a relative -Prefix value'; Code = 'Import-Module -Prefix ./X -Name Pester' }
            @{ Name = 'a relative -ArgumentList value'; Code = 'Import-Module Pester -ArgumentList ./X' }
            @{ Name = 'Test-Path on a dot-slash script'; Code = 'Test-Path -LiteralPath ''.\Helper.ps1''' }
            @{ Name = 'Copy-Item of a dot-slash script'; Code = "`$dest = 'C:\Temp'`nCopy-Item '.\Helper.ps1' `$dest" }
            @{ Name = 'Get-Content of a dot-slash script'; Code = 'Get-Content .\Helper.psm1' }
            @{ Name = 'a dot-slash script path assigned and never loaded'; Code = '$helper = ''.\Helper.ps1''' }
            @{ Name = 'a dot-slash script variable used only by Test-Path'; Code = "`$helper = '.\Helper.ps1'`nTest-Path `$helper" }
            @{ Name = 'a Join-Path from $PWD that is never loaded'; Code = "`$out = Join-Path `$PWD 'Report.ps1'`nSet-Content -Path `$out -Value 'x'" }
            @{ Name = 'Join-Path from a variable holding $PSScriptRoot'; Code = "`$base = `$PSScriptRoot`n. (Join-Path `$base 'Helper.ps1')" }
            @{ Name = 'Join-Path from an environment variable'; Code = 'Import-Module (Join-Path $env:ProgramFiles ''Helper'')' }
            @{ Name = 'a dot-source of an interpolated $PSScriptRoot path'; Code = '. $PSScriptRoot\Helper.ps1' }
            @{ Name = 'the call operator on a Join-Path $PSScriptRoot script'; Code = '& (Join-Path $PSScriptRoot ''Helper.ps1'')' }
            @{ Name = 'the call operator on a module-qualified command'; Code = '& ''Microsoft.PowerShell.Utility\Write-Output'' x' }
            @{ Name = 'the call operator on a script block'; Code = '& { Get-Item .\Helper.ps1 }' }
            @{ Name = 'the call operator on a variable holding a script block'; Code = "`$work = { Get-Item .\Helper.ps1 }`n& `$work" }
            @{ Name = 'the call operator on a command name held in a variable'; Code = "`$cmd = 'Get-Item'`n& `$cmd x" }
            @{ Name = 'a dot-source of a script name found on PATH'; Code = '. Helper.ps1' }
            @{ Name = 'a dot-slash native executable'; Code = '.\devcon.exe find =display' }
            @{ Name = 'the call operator on a Join-Path $PWD executable'; Code = '& (Join-Path $PWD ''tool.exe'') /q' }
            @{ Name = 'a UNC module path'; Code = 'Import-Module ''\\server\share\Helper.psm1''' }
            @{ Name = 'a dot-source of a UNC script path'; Code = '. ''\\server\share\Helper.ps1''' }
            @{ Name = 'a forward-slash absolute module path'; Code = 'Import-Module ''C:/Modules/Helper''' }
            @{ Name = 'Join-Path from a bare drive (C: joins to C:\)'; Code = 'Import-Module (Join-Path ''C:'' ''Helper.psm1'')' }
            @{ Name = 'a PowerShell-drive module path'; Code = 'Import-Module ''TestDrive:\Helper.psm1''' }
            @{ Name = 'an interpolated anchored module path'; Code = 'Import-Module "$PSScriptRoot\lib\$name"' }
            @{ Name = 'an interpolated module name held in a variable'; Code = "`$m = 'Pester'`nImport-Module `"`$m`"" }
            @{ Name = 'an interpolated UNC module path'; Code = 'Import-Module "\\server\share\$name"' }
            @{ Name = 'an interpolated absolute module path'; Code = 'Import-Module "C:\Modules\$name"' }
            @{ Name = 'the call operator on Join-Path $PWD with an interpolated .exe'; Code = '& (Join-Path $PWD "$tool.exe")' }
            @{ Name = 'an anchored concatenated module path'; Code = 'Import-Module ($PSScriptRoot + ''\Helper.psm1'')' }
            @{ Name = 'the call operator on a concatenated $PWD executable'; Code = '& ($PWD.Path + ''\tool.exe'')' }
            @{ Name = 'a double-quoted import by module name'; Code = 'Import-Module "Pester"' }
            @{ Name = 'an interpolated $env: executable path'; Code = '& "$env:windir\System32\tool.exe" /q' }
            @{ Name = 'Join-Path from [Environment]::GetFolderPath'; Code = '. (Join-Path ([Environment]::GetFolderPath(''ProgramFiles'')) ''Helper.ps1'')' }
            @{ Name = 'Join-Path from [Environment]::SystemDirectory'; Code = '& (Join-Path ([Environment]::SystemDirectory) $file)' }
            # C6: wrappers around a non-script child, and unknown children under a rooted parent.
            @{ Name = 'the call operator on Join-Path $PWD with a parenthesized .exe'; Code = '& (Join-Path $PWD (''tool.exe''))' }
            @{ Name = 'the call operator on Join-Path $PWD with a cast .exe'; Code = '& (Join-Path $PWD ([string]$(''tool.exe'')))' }
            @{ Name = 'the call operator on Join-Path $PWD with a variable holding an .exe'; Code = "`$tool = 'tool.exe'`n& (Join-Path `$PWD `$tool)" }
            @{ Name = 'the call operator on Join-Path $PSScriptRoot with a variable child'; Code = '& (Join-Path $PSScriptRoot $file)' }
            @{ Name = 'a dot-source of Join-Path from a parenthesized $PSScriptRoot'; Code = '. (Join-Path ($PSScriptRoot) $file)' }
            @{ Name = 'the call operator on Join-Path from an environment variable with a variable child'; Code = '& (Join-Path $env:ProgramFiles $file)' }
            @{ Name = 'the call operator on Join-Path from a bare drive with a variable child'; Code = '& (Join-Path ''C:'' $file)' }
            @{ Name = 'Join-Path $PWD with a variable child, never loaded'; Code = '$out = Join-Path $PWD $file' }
            @{ Name = 'a parenthesized import by module name'; Code = 'Import-Module (''Pester'')' }
            # Round 5 findings, one or more fixtures each.
            @{ Name = '4702662099: a Join-Path -Verbose switch before the parent'; Code = 'Import-Module (Join-Path -Verbose $PSScriptRoot ''Helper.psm1'')' }
            @{ Name = '4702662099: a Join-Path -Debug switch before the parent'; Code = 'Import-Module (Join-Path -Debug $PSScriptRoot ''Helper.psm1'')' }
            @{ Name = '4702662099: a Join-Path -Verbose switch before an .exe child'; Code = '& (Join-Path $PWD -Verbose ''tool.exe'')' }
            @{ Name = '4702662099: a Join-Path -Resolve switch before the parent'; Code = 'Import-Module (Join-Path -Resolve $PSScriptRoot ''Helper.psm1'')' }
            @{ Name = '4702662152: a positional child before a named -Path'; Code = 'Import-Module (Join-Path ''Helper.psm1'' -Path $PSScriptRoot)' }
            @{ Name = '4702662191: a $script:-scoped anchored base read unqualified'; Code = "`$script:base = `$PSScriptRoot`nImport-Module (Join-Path `$base 'Helper.psm1')" }
            @{ Name = '4702662238: a concatenated .exe child under $PWD'; Code = '& (Join-Path $PWD (''tool.'' + ''exe''))' }
            @{ Name = '4702662280: a module name built from two constant variables'; Code = "`$prefix = 'Helper'`n`$suffix = 'Tools'`nImport-Module `"`$prefix-`$suffix`"" }
            @{ Name = '4702662310: an anchored splat through a variable alias'; Code = "`$original = @{ Name = `"`$PSScriptRoot\Helper.psm1`" }`n`$copy = `$original`nImport-Module @copy" }
            @{ Name = '4702665676: a plain .exe assignment stays a non-script'; Code = "`$file = 'tool.exe'`n& (Join-Path `$PWD `$file)" }
            @{ Name = '4702665687: an interpolated $PSScriptRoot path with forward slashes'; Code = 'Import-Module "$PSScriptRoot/Helper.psm1"' }
            @{ Name = '4702665698: a dot-slash .exe split across a concatenation'; Code = '& (''./tool.'' + ''exe'')' }
            @{ Name = '4702665705: a module name split across a concatenation'; Code = 'Import-Module (''Pes'' + ''ter'')' }
            @{ Name = '4702665716: -vb before a module name'; Code = 'Import-Module -vb Pester' }
            @{ Name = '4702665716: -ErrorAction still takes a value'; Code = 'Import-Module -ErrorAction Stop Pester' }
            # Suppression and item sources.
            @{ Name = 'a suppression comment on the line above'; Code = "# relative-import-ok: the caller always runs it from the repo root`nImport-Module .\Helper.psm1" }
            @{ Name = 'a suppression comment at the end of the line'; Code = 'Import-Module .\Helper.psm1 # relative-import-ok: the caller always runs it from the repo root' }
            @{ Name = 'a foreach variable over Get-ChildItem of $PSScriptRoot'; Code = "foreach (`$file in Get-ChildItem -Path `$PSScriptRoot -Filter *.ps1) {`n. `$file.FullName`n}" }
            @{ Name = 'ForEach-Object over Get-ChildItem of an anchored folder'; Code = 'Get-ChildItem "$PSScriptRoot\lib" -Filter *.ps1 | Where-Object { $_.Name -ne ''x.ps1'' } | ForEach-Object { . $_.FullName }' }
            @{ Name = 'a foreach over two Get-ChildItem results joined with +'; Code = "`$a = @(Get-ChildItem -Path (Join-Path `$PSScriptRoot 'Private') -Filter '*.ps1' -File -ErrorAction SilentlyContinue)`n`$b = @(Get-ChildItem -Path (Join-Path `$PSScriptRoot 'Public') -File)`nforeach (`$file in @(`$a + `$b)) {`n. `$file.FullName`n}" }
            @{ Name = 'a foreach variable over a list of module names'; Code = "foreach (`$m in @('Pester', 'PSScriptAnalyzer')) {`nImport-Module `$m`n}" }
        ) {
            param($Name, $Code)
            Invoke-FixtureScan -Code $Code | Should -BeNullOrEmpty
        }

        It 'does not scan module manifests, whose paths resolve against the manifest folder' {
            $root = Join-Path $TestDrive 'manifest'
            New-Item -ItemType Directory -Path (Join-Path $root 'Modules/M') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'Modules/M/M.psd1') -Value "@{ RootModule = '.\M.psm1'; NestedModules = @('.\Sub.psm1'); ScriptsToProcess = @('.\Init.ps1') }" -Encoding UTF8
            @(Get-RelativeImportOffender -Root $root) | Should -BeNullOrEmpty
        }
    }
}
