#Requires -Version 5.1
# Module skeleton checks: every Modules/<Name>/<Name>.psd1 follows the layout standard in
# README.md ("Modules"), passes Test-ModuleManifest, imports, and exports exactly what its
# manifest declares. Importing a module only defines its functions; nothing is called.

BeforeDiscovery {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $modulesRoot = Join-Path $repoRoot 'Modules'
    $script:moduleCases = @(
        Get-ChildItem -Path $modulesRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            @{ Name = $_.Name; ModuleFolder = $_.FullName; ManifestPath = Join-Path $_.FullName "$($_.Name).psd1" }
        }
    )
}

Describe 'Modules/ contains only module folders' {
    It 'contains at least one module, so the per-module checks below cannot pass vacuously' {
        $root = Join-Path (Split-Path -Parent $PSScriptRoot) 'Modules'
        $manifests = @(Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
                Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "$($_.Name).psd1") })
        $manifests.Count | Should -BeGreaterThan 0 -Because 'Modules/<Name>/<Name>.psd1 must exist for at least one module'
    }

    It 'has no loose files' {
        $root = Join-Path (Split-Path -Parent $PSScriptRoot) 'Modules'
        Get-ChildItem -Path $root -File -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Name } |
            Should -BeNullOrEmpty -Because 'scripts belong under Scripts/<Category>/ and every module lives in Modules/<Name>/'
    }
}

Describe 'Module <Name>' -ForEach $script:moduleCases {
    BeforeAll {
        $manifestExists = Test-Path -LiteralPath $ManifestPath
        $data = if ($manifestExists) { Import-PowerShellDataFile -Path $ManifestPath } else { @{} }
        $declaredFunctions = @($data.FunctionsToExport | Where-Object { $_ } | Sort-Object)
        $declaredAliases = @($data.AliasesToExport | Where-Object { $_ } | Sort-Object)
    }

    AfterAll {
        Remove-Module -Name $Name -Force -ErrorAction SilentlyContinue
    }

    It 'has a manifest named after its folder' {
        $manifestExists | Should -BeTrue -Because "Modules/$Name/ must contain $Name.psd1"
    }

    It 'passes Test-ModuleManifest' {
        { Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'follows the manifest rules' {
        $data.RootModule | Should -Be "$Name.psm1"
        $data.PowerShellVersion | Should -Be '5.1'
        (@($data.CompatiblePSEditions | Sort-Object) -join ', ') | Should -Be 'Core, Desktop'
        $data.ContainsKey('RequiredModules') | Should -BeTrue -Because 'RequiredModules is declared even when empty'
        foreach ($key in 'AliasesToExport', 'CmdletsToExport', 'VariablesToExport') {
            $data.ContainsKey($key) | Should -BeTrue -Because "$key is declared even when empty"
        }
        $declaredFunctions | Should -Not -BeNullOrEmpty
        $allExports = @($declaredFunctions + $declaredAliases + @($data.CmdletsToExport) + @($data.VariablesToExport))
        @($allExports -match '\*') | Should -BeNullOrEmpty -Because 'export lists are explicit, never wildcards'
    }

    It 'lists every Public/*.ps1 in FunctionsToExport' {
        $publicNames = @(Get-ChildItem -Path (Join-Path $ModuleFolder 'Public') -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
                ForEach-Object { $_.BaseName } | Sort-Object)
        ($publicNames -join ', ') | Should -Be ($declaredFunctions -join ', ')
    }

    It 'defines exactly one top-level function, named after the file, in each Public/*.ps1' {
        # Parsed only, never dot-sourced or run. Helpers nested inside the function are allowed.
        foreach ($file in @(Get-ChildItem -Path (Join-Path $ModuleFolder 'Public') -Filter '*.ps1' -File -ErrorAction SilentlyContinue)) {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
            @($parseErrors) | Should -BeNullOrEmpty -Because "Public/$($file.Name) must parse"
            $topLevel = @($ast.FindAll({
                        param($node)
                        if ($node -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { return $false }
                        for ($p = $node.Parent; $p; $p = $p.Parent) {
                            if ($p -is [System.Management.Automation.Language.FunctionDefinitionAst]) { return $false }
                        }
                        return $true
                    }, $true) | ForEach-Object { $_.Name })
            ($topLevel -join ', ') | Should -Be $file.BaseName -Because "Public/$($file.Name) holds one exported function named after the file"
        }
    }

    It 'imports and exports exactly FunctionsToExport and AliasesToExport' {
        $module = Import-Module -Name $ManifestPath -Force -PassThru -ErrorAction Stop
        (@($module.ExportedFunctions.Keys | Sort-Object) -join ', ') | Should -Be ($declaredFunctions -join ', ')
        (@($module.ExportedAliases.Keys | Sort-Object) -join ', ') | Should -Be ($declaredAliases -join ', ')
        @($module.ExportedCmdlets.Keys) | Should -BeNullOrEmpty
    }
}
