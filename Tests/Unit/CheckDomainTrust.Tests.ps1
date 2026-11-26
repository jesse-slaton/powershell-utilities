BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Register-CommandStub -Name Resolve-DnsName -Parameter Name, Type
    Register-CommandStub -Name Get-CimInstance -Parameter ClassName
    $script:ScriptPath = Resolve-ScriptUnderTest -Name $PSCommandPath
    . (Get-ScriptFunctionDefinition -Path $script:ScriptPath)

    # nltest /sc_verify output in the shapes Windows prints it.
    $script:Healthy = @(
        'Flags: b0 HAS_IP  HAS_TIMESERV'
        'Trusted DC Name \\dc01.corp.contoso.com'
        'Trusted DC Connection Status Status = 0 0x0 NERR_Success'
        'Trust Verification Status = 0 0x0 NERR_Success'
        'The command completed successfully'
    )
    $script:NoLogonServers = @(
        'Flags: 0'
        'Trusted DC Name'
        'Trusted DC Connection Status Status = 1311 0x51f ERROR_NO_LOGON_SERVERS'
        'Trust Verification Status = 1311 0x51f ERROR_NO_LOGON_SERVERS'
        'The command completed successfully'
    )
}

AfterAll {
    Remove-CommandStub -Name Resolve-DnsName
    Remove-CommandStub -Name Get-CimInstance
}

Describe 'CheckDomainTrust.ps1' {
    It 'no longer calls Test-ComputerSecureChannel, which PowerShell 7 does not have' {
        $Tokens = $null
        $ParseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$Tokens, [ref]$ParseErrors)
        @($Tokens | Where-Object { $_.Kind -ne 'Comment' -and $_.Text -match 'Test-ComputerSecureChannel' }) | Should -BeNullOrEmpty
    }

    Context '-DomainName' {
        BeforeAll {
            $script:Parameter = (Get-Command -Name $script:ScriptPath).Parameters['DomainName']
            $script:Pattern = ($script:Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidatePatternAttribute] }).RegexPattern
        }

        It 'is optional, so the script still runs with no arguments' {
            ($script:Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeFalse
        }

        It 'is resolved through Get-TargetDomainName before the check runs' {
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$null)
            $Top = $Ast.EndBlock.Statements | Where-Object { $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst] }
            "$Top" | Should -Match 'Test-DomainSecureChannel -DomainName \(Get-TargetDomainName -DomainName \$DomainName\)'
        }

        It 'accepts a DNS domain name' {
            'corp.contoso.com' | Should -Match $script:Pattern
            'CONTOSO' | Should -Match $script:Pattern
        }

        It 'rejects a value that would add nltest arguments' {
            'corp.contoso.com /sc_reset:corp.contoso.com' | Should -Not -Match $script:Pattern
            'corp.contoso.com"' | Should -Not -Match $script:Pattern
            '' | Should -Not -Match $script:Pattern
        }
    }
}

Describe 'Get-TargetDomainName' {
    It 'returns the domain the computer is joined to when no domain is given' {
        Mock Get-CimInstance { [pscustomobject]@{ PartOfDomain = $true; Domain = 'corp.contoso.com' } }
        Get-TargetDomainName | Should -BeExactly 'corp.contoso.com'
        Should -Invoke Get-CimInstance -Times 1 -Exactly -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' }
    }

    It 'throws when the computer is not joined to a domain' {
        Mock Get-CimInstance { [pscustomobject]@{ PartOfDomain = $false; Domain = 'WORKGROUP' } }
        { Get-TargetDomainName } | Should -Throw '*not joined to a domain*-DomainName*'
    }

    It 'throws instead of passing an odd joined-domain name to nltest' {
        Mock Get-CimInstance { [pscustomobject]@{ PartOfDomain = $true; Domain = 'corp.contoso.com /sc_reset:x' } }
        { Get-TargetDomainName } | Should -Throw '*not a DNS domain name*'
    }

    It 'returns -DomainName unchanged, without looking up the joined domain' {
        Mock Get-CimInstance { [pscustomobject]@{ PartOfDomain = $true; Domain = 'joined.contoso.com' } }
        Get-TargetDomainName -DomainName 'other.contoso.com' | Should -BeExactly 'other.contoso.com'
        Should -Invoke Get-CimInstance -Times 0 -Exactly
    }
}

Describe 'ConvertFrom-NltestScVerify' {
    It 'returns True when both statuses are NERR_Success and nltest exits 0' {
        ConvertFrom-NltestScVerify -ExitCode 0 -Output $script:Healthy | Should -BeExactly $true
    }

    It 'returns False when nltest reports ERROR_NO_LOGON_SERVERS' {
        ConvertFrom-NltestScVerify -ExitCode 0 -Output $script:NoLogonServers | Should -BeExactly $false
    }

    It 'returns False when nltest fails with ERROR_TRUSTED_RELATIONSHIP_FAILURE' {
        $Output = 'I_NetLogonControl failed: Status = 1789 0x6fd ERROR_TRUSTED_RELATIONSHIP_FAILURE'
        ConvertFrom-NltestScVerify -ExitCode 1789 -Output $Output | Should -BeExactly $false
    }

    It 'reads the status codes, not the labels, so a localized display language still works' {
        $German = @(
            'Kennzeichen: b0 HAS_IP  HAS_TIMESERV'
            'Vertrauenswuerdiger Domaenencontroller \\dc01.corp.contoso.com'
            'Verbindungsstatus = 0 0x0 NERR_Success'
            'Vertrauensueberpruefung = 0 0x0 NERR_Success'
        )
        ConvertFrom-NltestScVerify -ExitCode 0 -Output $German | Should -BeExactly $true
    }

    It 'returns False when nltest exits 0 but the DC connection status is an error such as access denied' {
        $Output = @(
            'Flags: 0'
            'Trusted DC Name'
            'Trusted DC Connection Status Status = 5 0x5 ERROR_ACCESS_DENIED'
            'Trust Verification Status = 0 0x0 NERR_Success'
            'The command completed successfully'
        )
        ConvertFrom-NltestScVerify -ExitCode 0 -Output $Output | Should -BeExactly $false
    }

    It 'throws, quoting nltest, when it cannot check the channel (access denied)' {
        $Output = 'I_NetLogonControl failed: Status = 5 0x5 ERROR_ACCESS_DENIED'
        { ConvertFrom-NltestScVerify -ExitCode 5 -Output $Output } | Should -Throw '*could not check the secure channel (exit code 5)*ERROR_ACCESS_DENIED*'
    }

    It 'throws for an unknown domain instead of answering False' {
        $Output = 'I_NetLogonControl failed: Status = 1355 0x54b ERROR_NO_SUCH_DOMAIN'
        { ConvertFrom-NltestScVerify -ExitCode 1355 -Output $Output } | Should -Throw '*ERROR_NO_SUCH_DOMAIN*'
    }

    It 'throws when nltest exits non-zero even though every status is 0' {
        { ConvertFrom-NltestScVerify -ExitCode 1 -Output $script:Healthy } | Should -Throw '*exit code 1*'
    }

    It 'throws when the output holds no status at all' {
        { ConvertFrom-NltestScVerify -ExitCode 0 -Output @() } | Should -Throw '*printed no status*'
        { ConvertFrom-NltestScVerify -ExitCode 9009 -Output "'nltest.exe' is not recognized" } | Should -Throw '*printed no status (exit code 9009)*'
    }
}

Describe 'Invoke-NltestScVerify' {
    BeforeAll {
        # A function shadows nltest.exe during command lookup, so nltest never runs.
        function global:nltest.exe {
            $global:CdtTestArgs = $args
            $global:LASTEXITCODE = 1789
            'I_NetLogonControl failed: Status = 1789 0x6fd ERROR_TRUSTED_RELATIONSHIP_FAILURE'
        }
    }

    AfterAll {
        Remove-Item -LiteralPath 'Function:\nltest.exe' -ErrorAction SilentlyContinue
        Remove-Variable -Name CdtTestArgs -Scope Global -ErrorAction SilentlyContinue
    }

    It 'passes the domain as one /sc_verify argument and returns the exit code and output' {
        $Result = Invoke-NltestScVerify -DomainName 'corp.contoso.com'
        @($global:CdtTestArgs) | Should -Be @('/sc_verify:corp.contoso.com')
        $Result.ExitCode | Should -Be 1789
        $Result.Output | Should -Be @('I_NetLogonControl failed: Status = 1789 0x6fd ERROR_TRUSTED_RELATIONSHIP_FAILURE')
    }
}

Describe 'Test-DomainSecureChannel' {
    BeforeEach {
        Mock Invoke-NltestScVerify { [pscustomobject]@{ ExitCode = 0; Output = $script:Healthy } }
    }

    It 'returns the resolution message and runs no nltest when no SRV record resolves' {
        Mock Resolve-DnsName { }
        Test-DomainSecureChannel -DomainName 'corp.contoso.com' | Should -BeExactly 'Unable to resolve domain controller addresses.'
        Should -Invoke Invoke-NltestScVerify -Times 0 -Exactly
    }

    It 'ignores answers that are not SRV records' {
        Mock Resolve-DnsName { [pscustomobject]@{ Type = 'A'; Section = 'Additional'; Name = 'dc01.corp.contoso.com'; IPAddress = '192.0.2.10' } }
        Test-DomainSecureChannel -DomainName 'corp.contoso.com' | Should -BeExactly 'Unable to resolve domain controller addresses.'
        Should -Invoke Invoke-NltestScVerify -Times 0 -Exactly
    }

    It 'looks up the domain controller SRV records of the given domain' {
        Mock Resolve-DnsName { [pscustomobject]@{ Type = 'SRV'; Section = 'Answer'; Name = '_ldap._tcp.dc._msdcs.corp.contoso.com'; NameTarget = 'dc01.corp.contoso.com'; Port = 389 } }
        $null = Test-DomainSecureChannel -DomainName 'corp.contoso.com'
        Should -Invoke Resolve-DnsName -Times 1 -Exactly -ParameterFilter { $Name -eq '_ldap._tcp.dc._msdcs.corp.contoso.com' -and $Type -eq 'SRV' }
    }

    It 'returns True for a healthy channel, checking the given domain' {
        Mock Resolve-DnsName { [pscustomobject]@{ Type = 'SRV'; Section = 'Answer'; Name = '_ldap._tcp.dc._msdcs.corp.contoso.com'; NameTarget = 'dc01.corp.contoso.com'; Port = 389 } }
        Test-DomainSecureChannel -DomainName 'corp.contoso.com' | Should -BeExactly $true
        Should -Invoke Invoke-NltestScVerify -Times 1 -Exactly -ParameterFilter { $DomainName -eq 'corp.contoso.com' }
    }

    It 'returns False for a broken channel' {
        Mock Resolve-DnsName { [pscustomobject]@{ Type = 'SRV'; Section = 'Answer'; Name = '_ldap._tcp.dc._msdcs.corp.contoso.com'; NameTarget = 'dc01.corp.contoso.com'; Port = 389 } }
        Mock Invoke-NltestScVerify { [pscustomobject]@{ ExitCode = 0; Output = $script:NoLogonServers } }
        Test-DomainSecureChannel -DomainName 'corp.contoso.com' | Should -BeExactly $false
    }

    It 'lets an nltest failure stop the caller' {
        Mock Resolve-DnsName { [pscustomobject]@{ Type = 'SRV'; Section = 'Answer'; Name = '_ldap._tcp.dc._msdcs.corp.contoso.com'; NameTarget = 'dc01.corp.contoso.com'; Port = 389 } }
        Mock Invoke-NltestScVerify { [pscustomobject]@{ ExitCode = 5; Output = @('I_NetLogonControl failed: Status = 5 0x5 ERROR_ACCESS_DENIED') } }
        { Test-DomainSecureChannel -DomainName 'corp.contoso.com' } | Should -Throw '*ERROR_ACCESS_DENIED*'
    }
}
