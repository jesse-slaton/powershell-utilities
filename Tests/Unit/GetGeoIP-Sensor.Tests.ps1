BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    $script:ScriptPath = Resolve-ScriptUnderTest -Name $PSCommandPath
    . (Get-ScriptFunctionDefinition -Path $script:ScriptPath)
}

Describe 'Get-GeoIP' {
    BeforeEach {
        Mock Start-Sleep { }
        Mock Write-Progress { }
        Mock Invoke-RestMethod { [pscustomobject]@{ Country = 'Testland'; City = 'Testville'; Query = 'x' } }
    }

    It 'looks up a valid address: <Address>' -ForEach @(
        @{ Address = '8.8.8.8' }
        @{ Address = '0.0.0.0' }
        @{ Address = '255.255.255.255' }
        @{ Address = '10.0.200.249' }
        @{ Address = '010.001.0.1' }
    ) {
        $result = Get-GeoIP -IPAddress $Address
        $result.IPAddress | Should -Be $Address
        $result.Country | Should -Be 'Testland'
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Uri -eq "http://ip-api.com/json/$Address" }
    }

    It 'rejects <Address>, which is not a whole IPv4 address' -ForEach @(
        @{ Address = 'x8.8.8.8' }
        @{ Address = '8.8.8.8 and more' }
        @{ Address = 'http://8.8.8.8/' }
        @{ Address = '256.1.1.1' }
        @{ Address = '1.2.3.300' }
        @{ Address = '1.2.3.4.5' }
        @{ Address = "1.2.3.4`n" }
        @{ Address = '1.2.3' }
        @{ Address = '2001:db8::1' }
    ) {
        { Get-GeoIP -IPAddress $Address } | Should -Throw -ErrorId 'ParameterArgumentValidationError,Get-GeoIP'
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }

    It 'warns and moves on when a lookup writes an error' {
        Mock Invoke-RestMethod { Write-Error 'service unavailable' } -ParameterFilter { $Uri -like '*/1.1.1.1' }
        $result = @(Get-GeoIP -IPAddress '1.1.1.1', '8.8.8.8' -WarningVariable warnings -WarningAction SilentlyContinue)
        @($warnings).Count | Should -Be 1
        "$($warnings[0])" | Should -Be '1.1.1.1 : service unavailable'
        $result.Count | Should -Be 1
        $result[0].IPAddress | Should -Be '8.8.8.8'
    }

    It 'warns when a lookup throws' {
        Mock Invoke-RestMethod { throw 'no network' }
        $result = Get-GeoIP -IPAddress '8.8.8.8' -WarningVariable warnings -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$($warnings[0])" | Should -Be '8.8.8.8 : no network'
    }
}

Describe 'Get-GeoIP help examples' {
    It 'uses only commands that exist on Windows' {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$tokens, [ref]$errors)
        $function = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-GeoIP' }, $true)
        $examples = @($function.GetHelpContent().Examples)
        $examples.Count | Should -BeGreaterThan 0

        # Built-in Windows commands that are missing off Windows, so Get-Command cannot confirm them here.
        $windowsOnly = @('Get-NetTCPConnection')
        $unknown = foreach ($example in $examples) {
            $exampleAst = [System.Management.Automation.Language.Parser]::ParseInput($example, [ref]$tokens, [ref]$errors)
            foreach ($command in $exampleAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                $name = $command.GetCommandName()
                if ($name -and $name -ne 'Get-GeoIP' -and $windowsOnly -notcontains $name -and -not (Get-Command -Name $name -ErrorAction SilentlyContinue)) {
                    $name
                }
            }
        }
        @($unknown) | Should -BeNullOrEmpty
    }
}
