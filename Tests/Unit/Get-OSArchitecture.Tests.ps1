BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Register-CommandStub -Name Get-CimInstance -Parameter Namespace, ClassName
    $script:Definition = Get-ScriptFunctionDefinition -Path (Resolve-ScriptUnderTest -Name $PSCommandPath)
    . $script:Definition
}

AfterAll {
    Remove-CommandStub -Name Get-CimInstance
}

Describe 'Get-OSArchitecture' {
    It 'returns <Expected> for AddressWidth <Width>' -ForEach @(
        @{ Width = 64; Expected = 'AMD64' }
        @{ Width = 32; Expected = 'x86' }
        @{ Width = 16; Expected = 'Unknown' }
    ) {
        Mock Get-CimInstance {
            @([pscustomobject]@{ DeviceID = 'CPU1'; AddressWidth = 0 }, [pscustomobject]@{ DeviceID = 'CPU0'; AddressWidth = $Width })
        }
        Get-OSArchitecture | Should -Be $Expected
    }

    It 'returns Unknown when there is no CPU0' {
        Mock Get-CimInstance { [pscustomobject]@{ DeviceID = 'CPU1'; AddressWidth = 64 } }
        Get-OSArchitecture | Should -Be 'Unknown'
    }

    It 'throws on a failed CIM query instead of ending the PowerShell process' {
        # Run in a background job: if the function ends its process (the old
        # [Environment]::Exit), only the job's process dies, not this test run.
        $job = Start-Job -ScriptBlock {
            param ($Definition)
            . ([scriptblock]::Create($Definition))
            function Get-CimInstance { throw 'CIM is unavailable' }
            try {
                Get-OSArchitecture
                'no error'
            }
            catch {
                "caught: $($_.Exception.Message)"
            }
            'process still running'
        } -ArgumentList $script:Definition.ToString()
        try {
            $null = Wait-Job -Job $job -Timeout 120
            $output = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
        }
        finally {
            Remove-Job -Job $job -Force
        }
        $output | Should -Contain 'caught: CIM is unavailable'
        $output | Should -Contain 'process still running'
    }
}
