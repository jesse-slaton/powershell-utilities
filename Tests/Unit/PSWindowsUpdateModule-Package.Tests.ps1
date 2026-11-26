BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    # Install-PSResource is missing from stock Windows PowerShell 5.1, and the PowerShellGet
    # 1.x bootstrap commands may be missing from PowerShell 7 off Windows.
    Register-CommandStub -Name Install-PSResource -Parameter Name, Repository, Scope -Switch TrustRepository, AcceptLicense, Quiet
    Register-CommandStub -Name Install-Module -Parameter Name, Repository, Scope -Switch Force
    Register-CommandStub -Name Install-PackageProvider, Register-PSRepository -Parameter Name
    $script:ScriptPath = Resolve-ScriptUnderTest -Name $PSCommandPath
    . (Get-ScriptFunctionDefinition -Path $script:ScriptPath)
}

AfterAll {
    Remove-CommandStub -Name Install-PSResource, Install-Module, Install-PackageProvider, Register-PSRepository
}

Describe 'Get-ModuleInstaller' {
    It 'prefers Install-PSResource when PSResourceGet is available' {
        Mock Get-Command { [pscustomobject]@{ Name = $Name } }

        Get-ModuleInstaller -Edition Desktop | Should -Be 'Install-PSResource'
        Get-ModuleInstaller -Edition Core | Should -Be 'Install-PSResource'
    }

    It 'falls back to Install-Module on Windows PowerShell 5.1 without PSResourceGet' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Install-PSResource' }
        Mock Get-Command { [pscustomobject]@{ Name = $Name } } -ParameterFilter { $Name -eq 'Install-Module' }

        Get-ModuleInstaller -Edition Desktop | Should -Be 'Install-Module'
    }

    It 'throws on PowerShell 7 without PSResourceGet instead of falling back' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Install-PSResource' }
        Mock Get-Command { [pscustomobject]@{ Name = $Name } } -ParameterFilter { $Name -eq 'Install-Module' }

        { Get-ModuleInstaller -Edition Core } | Should -Throw '*Install-PSResource is not available*'
    }

    It 'names the edition it decided for in the error' {
        Mock Get-Command { $null }

        { Get-ModuleInstaller -Edition Core } | Should -Throw '*this Core edition PowerShell host*'
        { Get-ModuleInstaller -Edition Desktop } | Should -Throw '*this Desktop edition PowerShell host*'
    }
}

Describe 'Enable-Tls12ForProcess' {
    It 'adds Tls12 and keeps the protocols already enabled' {
        $Saved = [System.Net.ServicePointManager]::SecurityProtocol
        try {
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls

            Enable-Tls12ForProcess

            $Now = [System.Net.ServicePointManager]::SecurityProtocol
            $Now | Should -Be ([System.Net.SecurityProtocolType]::Tls -bor [System.Net.SecurityProtocolType]::Tls12)
        }
        finally {
            [System.Net.ServicePointManager]::SecurityProtocol = $Saved
        }
    }
}

Describe 'Install-PSWindowsUpdateModule' {
    BeforeEach {
        Mock Install-PSResource { }
        Mock Install-Module { }
        Mock Install-PackageProvider { }
        Mock Register-PSRepository { }
        Mock Set-ItemProperty { }
        $script:Calls = [System.Collections.Generic.List[string]]::new()
        Mock Enable-Tls12ForProcess { $script:Calls.Add('Enable-Tls12ForProcess') }
    }

    It 'does nothing when PSWindowsUpdate is already installed' {
        Mock Get-Module { [pscustomobject]@{ Name = 'PSWindowsUpdate' } } -ParameterFilter { $Name -eq 'PSWindowsUpdate' }

        Install-PSWindowsUpdateModule | Should -Be 'PSWindowsUpdate Module is Already Installed.'
        Should -Invoke Install-PSResource -Times 0 -Exactly
        Should -Invoke Install-Module -Times 0 -Exactly
    }

    Context 'when PSWindowsUpdate is missing' {
        BeforeEach {
            Mock Get-Module { } -ParameterFilter { $Name -eq 'PSWindowsUpdate' }
        }

        It 'installs it for all users from PSGallery with Install-PSResource' {
            Mock Get-ModuleInstaller { 'Install-PSResource' }

            Install-PSWindowsUpdateModule | Should -Be 'Installing PSWindowsUpdate with Install-PSResource'
            Should -Invoke Install-PSResource -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'PSWindowsUpdate' -and $Repository -eq 'PSGallery' -and $Scope -eq 'AllUsers' -and $TrustRepository
            }
            Should -Invoke Install-Module -Times 0 -Exactly
        }

        It 'uses Install-Module only when that is the chosen fallback' {
            Mock Get-ModuleInstaller { 'Install-Module' }
            Mock Install-Module { $script:Calls.Add('Install-Module') }

            Install-PSWindowsUpdateModule | Should -Be 'Installing PSWindowsUpdate with Install-Module'
            Should -Invoke Install-Module -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'PSWindowsUpdate' -and $Repository -eq 'PSGallery' -and $Scope -eq 'AllUsers' -and $Force
            }
            Should -Invoke Install-PSResource -Times 0 -Exactly
            Should -Invoke Enable-Tls12ForProcess -Times 1 -Exactly
            $script:Calls -join ',' | Should -Be 'Enable-Tls12ForProcess,Install-Module'
        }

        It 'writes no registry values, registers no repository and leaves session TLS alone' {
            Mock Get-ModuleInstaller { 'Install-PSResource' }
            # Start from a value without Tls12, so adding it would show.
            $Saved = [System.Net.ServicePointManager]::SecurityProtocol
            try {
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls

                Install-PSWindowsUpdateModule | Out-Null

                [System.Net.ServicePointManager]::SecurityProtocol | Should -Be ([System.Net.SecurityProtocolType]::Tls)
            }
            finally {
                [System.Net.ServicePointManager]::SecurityProtocol = $Saved
            }
            Should -Invoke Set-ItemProperty -Times 0 -Exactly
            Should -Invoke Register-PSRepository -Times 0 -Exactly
            Should -Invoke Install-PackageProvider -Times 0 -Exactly
            Should -Invoke Enable-Tls12ForProcess -Times 0 -Exactly
        }

        It 'stops when the install fails' {
            Mock Get-ModuleInstaller { 'Install-PSResource' }
            Mock Install-PSResource { throw 'gallery unreachable' }

            { Install-PSWindowsUpdateModule } | Should -Throw '*gallery unreachable*'
        }
    }
}

Describe 'PSWindowsUpdateModule-Package.ps1' {
    It 'has no registry TLS plumbing and touches ServicePointManager only in Enable-Tls12ForProcess' {
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$null)
        $Code = @($Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -or $n -is [System.Management.Automation.Language.ExpressionAst] }, $true) | ForEach-Object { $_.Extent.Text })
        $Code | Where-Object { $_ -match 'SchUseStrongCrypto|WebClient' } | Should -BeNullOrEmpty

        $Uses = @($Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.TypeExpressionAst] -and $n.TypeName.Name -match 'ServicePointManager$' }, $true))
        $Uses.Count | Should -BeGreaterThan 0
        foreach ($Use in $Uses) {
            $Parent = $Use.Parent
            while ($Parent -and $Parent -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { $Parent = $Parent.Parent }
            $Parent.Name | Should -Be 'Enable-Tls12ForProcess'
        }
    }
}
