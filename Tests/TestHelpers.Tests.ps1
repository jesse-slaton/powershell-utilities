#Requires -Version 5.1
# Self-tests for TestHelpers.psm1. They load Fixtures/CoverageSample.ps1 through the AST
# only (its top-level code throws) and never run any script under Scripts/ or Modules/.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TestHelpers.psm1') -Force
    $script:fixture = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'Fixtures/CoverageSample.ps1')).ProviderPath
    . (Get-ScriptFunctionDefinition -Path $script:fixture)
}

Describe 'Get-ScriptFunctionDefinition' {
    It 'defines the functions without running top-level code' {
        Get-CoverageSampleSign -Number 2 | Should -Be 'positive'
        Get-CoverageSampleSign -Number 0 | Should -Be 'not positive'
        Get-CoverageSampleGreeting 'there' | Should -Be 'hello there'
    }

    It 'keeps the original file and start line on each function' {
        $sign = (Get-Command Get-CoverageSampleSign).ScriptBlock
        $sign.File | Should -Be $script:fixture
        $sign.StartPosition.StartLine | Should -Be 12
        (Get-Command Get-CoverageSampleGreeting).ScriptBlock.StartPosition.StartLine | Should -Be 33
    }

    It 'loads only the named functions when -Name is given' {
        $definition = Get-ScriptFunctionDefinition -Path $script:fixture -Name Get-CoverageSampleGreeting
        $definition.Ast.EndBlock.Statements.Count | Should -Be 1
        $definition.Ast.EndBlock.Statements[0].Name | Should -Be 'Get-CoverageSampleGreeting'
    }

    It 'leaves loaded functions mockable' {
        Mock Get-CoverageSampleGreeting { 'mocked' }
        Get-CoverageSampleGreeting 'x' | Should -Be 'mocked'
    }

    It 'lets a loaded function see a mock of the command it calls' {
        Mock Get-CoverageSampleGreeting { 'mocked' }
        Get-CoverageSampleReport | Should -Be 'report: mocked'
        Should -Invoke Get-CoverageSampleGreeting -Times 1 -Exactly
    }

    It 'returns only function text, so re-parsing it never runs top-level code' {
        $text = (Get-ScriptFunctionDefinition -Path $script:fixture).ToString()
        $text | Should -Not -BeLike '*top-level code ran*'
        $text | Should -Not -BeLike '*.SYNOPSIS*Fixture for*'
        { & ([scriptblock]::Create($text)) } | Should -Not -Throw
    }

    It 'reports Pester code coverage against the original path and lines' {
        # Run a nested Pester in a child process, so its coverage breakpoints do not
        # interfere with this run, and read back which fixture lines it saw execute.
        $inner = Join-Path $TestDrive 'Inner.Tests.ps1'
        $helpers = Join-Path $PSScriptRoot 'TestHelpers.psm1'
        Set-Content -LiteralPath $inner -Value @"
BeforeAll {
    Import-Module '$helpers' -Force
    . (Get-ScriptFunctionDefinition -Path '$script:fixture')
}
Describe 'inner' {
    It 'covers the positive branch only' { Get-CoverageSampleSign -Number 1 | Should -Be 'positive' }
}
"@
        $runner = Join-Path $TestDrive 'run.ps1'
        Set-Content -LiteralPath $runner -Value @"
Import-Module '$(Join-Path (Get-Module Pester | Select-Object -First 1).ModuleBase 'Pester.psd1')' -Force
`$config = New-PesterConfiguration
`$config.Run.Path = '$inner'
`$config.Run.PassThru = `$true
`$config.Output.Verbosity = 'None'
`$config.CodeCoverage.Enabled = `$true
`$config.CodeCoverage.Path = '$script:fixture'
`$config.CodeCoverage.OutputPath = '$(Join-Path $TestDrive 'coverage.xml')'
`$result = Invoke-Pester -Configuration `$config
@(
    @(`$result.CodeCoverage.CommandsExecuted | ForEach-Object { "hit `$(`$_.File)|`$(`$_.Line)" })
    @(`$result.CodeCoverage.CommandsMissed | ForEach-Object { "miss `$(`$_.File)|`$(`$_.Line)" })
) | Set-Content -LiteralPath '$(Join-Path $TestDrive 'lines.txt')'
"@
        $shell = (Get-Process -Id $PID).Path
        & $shell -NoProfile -NonInteractive -File $runner
        $LASTEXITCODE | Should -Be 0

        $lines = @(Get-Content -LiteralPath (Join-Path $TestDrive 'lines.txt'))
        $lines | Should -Contain "hit $script:fixture|25"
        $lines | Should -Contain "hit $script:fixture|26"
        $lines | Should -Contain "miss $script:fixture|29"
        $lines | Should -Contain "miss $script:fixture|34"
        Join-Path $TestDrive 'coverage.xml' | Should -Exist
    }
}

Describe 'Register-CommandStub' {
    AfterAll {
        Remove-CommandStub -Name Get-TestHelperStubSample, Get-TestHelperStubPipe
    }

    It 'does not replace a command that exists' {
        Register-CommandStub -Name Get-Date -Parameter Format
        (Get-Command Get-Date).CommandType | Should -Be 'Cmdlet'
    }

    It 'defines a missing command with the given parameters' {
        Register-CommandStub -Name Get-TestHelperStubSample -Parameter ClassName, Filter -Switch Force
        $command = Get-Command Get-TestHelperStubSample
        $command.CommandType | Should -Be 'Function'
        $command.Parameters.Keys | Should -Contain 'ClassName'
        $command.Parameters['Force'].ParameterType | Should -Be ([switch])
    }

    It 'throws when called without a mock' {
        { Get-TestHelperStubSample -ClassName X } | Should -Throw '*test stub*'
    }

    It 'works with Mock and -ParameterFilter, by name and by position' {
        Mock Get-TestHelperStubSample { 'adapters' } -ParameterFilter { $ClassName -eq 'Win32_NetworkAdapter' }
        Mock Get-TestHelperStubSample { 'other' }
        Get-TestHelperStubSample -ClassName Win32_NetworkAdapter -Force | Should -Be 'adapters'
        Get-TestHelperStubSample Win32_NetworkAdapter | Should -Be 'adapters'
        Get-TestHelperStubSample -ClassName Win32_Service -Unknown 1 | Should -Be 'other'
    }

    It 'replaces its own earlier stub with a new parameter list' {
        Register-CommandStub -Name Get-TestHelperStubSample -Parameter ComputerName
        $parameters = (Get-Command Get-TestHelperStubSample).Parameters.Keys
        $parameters | Should -Contain 'ComputerName'
        $parameters | Should -Not -Contain 'ClassName'
    }

    It 'rejects a parameter name that is not an identifier' {
        { Register-CommandStub -Name Get-TestHelperStubSample -Parameter 'bad name' } | Should -Throw '*Invalid parameter name*'
    }

    It 'rejects a common parameter name at registration' {
        { Register-CommandStub -Name Get-TestHelperStubSample -Switch Verbose } | Should -Throw '*common parameter*'
        { Register-CommandStub -Name Get-TestHelperStubSample -Parameter ErrorAction } | Should -Throw '*common parameter*'
    }

    It 'binds piped input to -PipelineParameter' {
        Register-CommandStub -Name Get-TestHelperStubPipe -Parameter Identity -PipelineParameter Identity
        Mock Get-TestHelperStubPipe { "got $Identity" }
        'bob', 'ann' | Get-TestHelperStubPipe | Should -Be 'got bob', 'got ann'
        Should -Invoke Get-TestHelperStubPipe -Times 1 -Exactly -ParameterFilter { $Identity -eq 'bob' }
    }

    It 'requires -PipelineParameter to be one of -Parameter' {
        { Register-CommandStub -Name Get-TestHelperStubPipe -Parameter Identity -PipelineParameter Name } | Should -Throw '*must also be listed*'
    }

    It 'Remove-CommandStub removes a stub and leaves other functions alone' {
        function global:Get-TestHelperNotAStub { 'real' }
        try {
            Register-CommandStub -Name Get-TestHelperStubGone
            Remove-CommandStub -Name Get-TestHelperStubGone, Get-TestHelperNotAStub, Get-Date
            Get-Command Get-TestHelperStubGone -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            Get-TestHelperNotAStub | Should -Be 'real'
            (Get-Command Get-Date).CommandType | Should -Be 'Cmdlet'
        }
        finally {
            Remove-Item -LiteralPath 'Function:\Get-TestHelperNotAStub', 'Function:\Get-TestHelperStubGone' -ErrorAction SilentlyContinue
        }
    }
}
