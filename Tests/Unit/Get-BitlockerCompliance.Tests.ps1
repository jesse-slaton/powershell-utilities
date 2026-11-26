BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    . (Get-ScriptFunctionDefinition -Path (Resolve-ScriptUnderTest -Name $PSCommandPath))

    # A throwaway value built at runtime; it is never a real secret.
    $script:TestPlain = 'Unit' + 'Test' + [guid]::NewGuid().ToString('N')
    $script:TestSecure = New-Object System.Security.SecureString
    foreach ($Char in $script:TestPlain.ToCharArray()) { $script:TestSecure.AppendChar($Char) }
    $script:TestCredential = New-Object System.Management.Automation.PSCredential -ArgumentList 'report_reader', $script:TestSecure

    # Stands in for a DirectorySearcher: FindAll returns $Result, or throws $Failure.
    function New-FakeSearcher {
        param ([object[]]$Result = @(), [string]$Failure)
        $Fake = New-Object PSObject
        $Fake | Add-Member -MemberType NoteProperty -Name Result -Value $Result
        $Fake | Add-Member -MemberType NoteProperty -Name Failure -Value $Failure
        $Fake | Add-Member -MemberType ScriptMethod -Name FindAll -Value {
            if ($this.Failure) { throw (New-Object System.Runtime.InteropServices.COMException -ArgumentList $this.Failure) }
            $this.Result
        }
        $Fake
    }

    # Stands in for an ADSI computer search result. As in a real SearchResult, every property
    # value is a one-element collection (ResultPropertyValueCollection), not a bare value.
    function New-FakeComputer {
        param ([string]$Name)
        [pscustomobject]@{
            Properties = @{
                name        = @($Name)
                whencreated = @([datetime]'2020-01-02')
                whenchanged = @([datetime]'2021-03-04')
            }
        }
    }
}

Describe 'New-ComplianceSqlConnection' {
    Context 'without a credential' {
        BeforeAll {
            $script:Connection = New-ComplianceSqlConnection -ServerInstance 'sql01.contoso.com' -Database 'CMDB' -ConnectionTimeout 45
            $script:Builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $script:Connection.ConnectionString
        }

        It 'returns an unopened SqlConnection' {
            $script:Connection | Should -BeOfType System.Data.SqlClient.SqlConnection
            $script:Connection.State | Should -Be 'Closed'
        }

        It 'uses Windows integrated security' {
            $script:Builder.IntegratedSecurity | Should -BeTrue
            $script:Connection.Credential | Should -BeNullOrEmpty
        }

        It 'carries the server, database and timeout' {
            $script:Builder.DataSource | Should -Be 'sql01.contoso.com'
            $script:Builder.InitialCatalog | Should -Be 'CMDB'
            $script:Builder.ConnectTimeout | Should -Be 45
        }

        It 'puts no SQL login keys in the connection string' {
            $script:Builder.UserID | Should -BeNullOrEmpty
            $script:Builder.Password | Should -BeNullOrEmpty
        }

        It 'treats PSCredential.Empty as no credential' {
            $Connection = New-ComplianceSqlConnection -ServerInstance 'sql01' -Database 'CMDB' -Credential ([System.Management.Automation.PSCredential]::Empty)
            (New-Object System.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $Connection.ConnectionString).IntegratedSecurity | Should -BeTrue
            $Connection.Credential | Should -BeNullOrEmpty
        }

        It 'escapes values so a parameter cannot inject connection-string keys' {
            $Connection = New-ComplianceSqlConnection -ServerInstance 'sql01' -Database 'CMDB;Integrated Security=False;User ID=x'
            $Builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $Connection.ConnectionString
            $Builder.InitialCatalog | Should -Be 'CMDB;Integrated Security=False;User ID=x'
            $Builder.IntegratedSecurity | Should -BeTrue
            $Builder.UserID | Should -BeNullOrEmpty
        }

        It 'keeps an injection attempt in -ServerInstance literal' {
            $Injected = 'sql01;Integrated Security=False;User ID=x;Password=y'
            $Connection = New-ComplianceSqlConnection -ServerInstance $Injected -Database 'CMDB'
            $Builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $Connection.ConnectionString
            $Builder.DataSource | Should -Be $Injected
            $Builder.InitialCatalog | Should -Be 'CMDB'
            $Builder.IntegratedSecurity | Should -BeTrue
            $Builder.UserID | Should -BeNullOrEmpty
            $Builder.Password | Should -BeNullOrEmpty
        }
    }

    Context 'with a SQL login credential' {
        BeforeAll {
            $script:Connection = New-ComplianceSqlConnection -ServerInstance 'sql01.contoso.com' -Database 'CMDB' -Credential $script:TestCredential
            $script:Builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $script:Connection.ConnectionString
        }

        It 'passes the login as a SqlCredential' {
            $script:Connection.Credential | Should -BeOfType System.Data.SqlClient.SqlCredential
            $script:Connection.Credential.UserId | Should -Be 'report_reader'
            $script:Connection.Credential.Password.IsReadOnly() | Should -BeTrue
        }

        It 'never writes the password or user into the connection string' {
            $script:Connection.ConnectionString | Should -Not -Match ([regex]::Escape($script:TestPlain))
            $script:Connection.ConnectionString | Should -Not -Match 'report_reader'
            $script:Builder.Password | Should -BeNullOrEmpty
            $script:Builder.UserID | Should -BeNullOrEmpty
        }

        It 'does not ask for integrated security' {
            $script:Builder.IntegratedSecurity | Should -BeFalse
        }

        It 'keeps an injection attempt in -Database literal' {
            $Injected = 'CMDB;Integrated Security=True;User ID=x;Password=y'
            $Connection = New-ComplianceSqlConnection -ServerInstance 'sql01' -Database $Injected -Credential $script:TestCredential
            $Builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $Connection.ConnectionString
            $Builder.InitialCatalog | Should -Be $Injected
            $Builder.IntegratedSecurity | Should -BeFalse
            $Builder.UserID | Should -BeNullOrEmpty
            $Builder.Password | Should -BeNullOrEmpty
            $Connection.Credential.UserId | Should -Be 'report_reader'
        }

        It 'keeps an injection attempt in -ServerInstance literal' {
            $Injected = 'sql01;Integrated Security=True;User ID=x;Password=y'
            $Connection = New-ComplianceSqlConnection -ServerInstance $Injected -Database 'CMDB' -Credential $script:TestCredential
            $Builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder -ArgumentList $Connection.ConnectionString
            $Builder.DataSource | Should -Be $Injected
            $Builder.IntegratedSecurity | Should -BeFalse
            $Builder.UserID | Should -BeNullOrEmpty
            $Builder.Password | Should -BeNullOrEmpty
        }

        It 'leaves the caller''s SecureString writable' {
            $script:TestCredential.Password.IsReadOnly() | Should -BeFalse
        }
    }
}

Describe 'ConvertTo-LdapPath' {
    It 'prefixes a distinguished name with LDAP://' {
        ConvertTo-LdapPath -Path 'OU=Computers,DC=contoso,DC=com' | Should -Be 'LDAP://OU=Computers,DC=contoso,DC=com'
    }

    It 'keeps an existing LDAP:// or GC:// path unchanged' {
        ConvertTo-LdapPath -Path 'LDAP://DC=contoso,DC=com' | Should -Be 'LDAP://DC=contoso,DC=com'
        ConvertTo-LdapPath -Path 'GC://DC=contoso,DC=com' | Should -Be 'GC://DC=contoso,DC=com'
    }

    It 'upper-cases a lower- or mixed-case provider prefix' {
        ConvertTo-LdapPath -Path 'ldap://OU=Computers,DC=contoso,DC=com' | Should -BeExactly 'LDAP://OU=Computers,DC=contoso,DC=com'
        ConvertTo-LdapPath -Path 'Gc://DC=contoso,DC=com' | Should -BeExactly 'GC://DC=contoso,DC=com'
    }

    It 'trims surrounding whitespace' {
        ConvertTo-LdapPath -Path '  OU=Computers,DC=contoso,DC=com ' | Should -BeExactly 'LDAP://OU=Computers,DC=contoso,DC=com'
        ConvertTo-LdapPath -Path ' LDAP://DC=contoso,DC=com  ' | Should -BeExactly 'LDAP://DC=contoso,DC=com'
    }

    It 'leaves the rest of the path as given' {
        ConvertTo-LdapPath -Path 'ldap://dc01.contoso.com/OU=Lab,DC=contoso,DC=com' | Should -BeExactly 'LDAP://dc01.contoso.com/OU=Lab,DC=contoso,DC=com'
    }
}

Describe 'Invoke-ComplianceAdSearch' {
    It 'returns every result of the search' {
        Mock New-ComplianceAdSearcher { New-FakeSearcher -Result (New-FakeComputer -Name 'PC01'), (New-FakeComputer -Name 'PC02') }
        $Results = @(Invoke-ComplianceAdSearch -Filter '(ObjectCategory=Computer)' -Property 'name' -SearchRoot 'OU=Computers,DC=contoso,DC=com')
        $Results.Count | Should -Be 2
        Should -Invoke New-ComplianceAdSearcher -Times 1 -Exactly -ParameterFilter { $SearchRoot -eq 'OU=Computers,DC=contoso,DC=com' }
    }

    It 'throws, naming the search root, when the search fails' {
        Mock New-ComplianceAdSearcher { New-FakeSearcher -Failure 'There is no such object on the server.' }
        { Invoke-ComplianceAdSearch -Filter '(ObjectCategory=Computer)' -Property 'name' -SearchRoot 'OU=Missing,DC=contoso,DC=com' } |
            Should -Throw "AD search of 'OU=Missing,DC=contoso,DC=com' failed: *no such object*"
    }

    It 'throws when the searcher cannot be built' {
        Mock New-ComplianceAdSearcher { throw 'simulated ADSI failure' }
        { Invoke-ComplianceAdSearch -Filter '(ObjectCategory=Computer)' -Property 'name' -SearchRoot 'DC=contoso,DC=com' } |
            Should -Throw "AD search of 'DC=contoso,DC=com' failed: *simulated ADSI failure*"
    }
}

Describe 'Get-ComplianceAdComputer' {
    It 'returns one row per computer with yyyy/MM/dd dates' {
        Mock New-ComplianceAdSearcher { New-FakeSearcher -Result (New-FakeComputer -Name 'PC02'), (New-FakeComputer -Name 'PC01') }
        $Rows = @(Get-ComplianceAdComputer -SearchRoot 'OU=Computers,DC=contoso,DC=com')
        $Rows.AD_Name | Should -Be @('PC01', 'PC02')
        $Rows[0].AD_Created | Should -Be '2020/01/02'
        $Rows[0].AD_Changed | Should -Be '2021/03/04'
    }

    It 'lists a computer once when search roots overlap' {
        Mock New-ComplianceAdSearcher { New-FakeSearcher -Result (New-FakeComputer -Name 'PC01'), (New-FakeComputer -Name 'PC02') } -ParameterFilter { $SearchRoot -eq 'OU=Computers,DC=contoso,DC=com' }
        Mock New-ComplianceAdSearcher { New-FakeSearcher -Result (New-FakeComputer -Name 'PC02'), (New-FakeComputer -Name 'PC03') } -ParameterFilter { $SearchRoot -eq 'OU=Lab,OU=Computers,DC=contoso,DC=com' }
        $Rows = @(Get-ComplianceAdComputer -SearchRoot 'OU=Computers,DC=contoso,DC=com', 'OU=Lab,OU=Computers,DC=contoso,DC=com')
        $Rows.AD_Name | Should -Be @('PC01', 'PC02', 'PC03')
    }

    It 'throws instead of reusing earlier results when a later search root fails' {
        Mock New-ComplianceAdSearcher { New-FakeSearcher -Result (New-FakeComputer -Name 'PC01') } -ParameterFilter { $SearchRoot -eq 'OU=Good,DC=contoso,DC=com' }
        Mock New-ComplianceAdSearcher { New-FakeSearcher -Failure 'Access is denied.' } -ParameterFilter { $SearchRoot -eq 'OU=Bad,DC=contoso,DC=com' }
        { Get-ComplianceAdComputer -SearchRoot 'OU=Good,DC=contoso,DC=com', 'OU=Bad,DC=contoso,DC=com' } |
            Should -Throw "AD search of 'OU=Bad,DC=contoso,DC=com' failed: *Access is denied*"
    }
}

# These tests run the whole script, an exception to the Tests/README.md rule, because the
# behavior under test is that the top-level code stops before it writes a report. The script
# changes no machine state; every command with an effect (CSV export, C:\Temp creation,
# console clearing, sleeps) is mocked, and the data sources are replaced by mocks that fail.
Describe 'Get-BitlockerCompliance.ps1 when a data source fails' {
    BeforeAll {
        $script:ScriptPath = Resolve-ScriptUnderTest -Name $PSCommandPath
        $script:RunParameters = @{
            ServerInstance     = 'sql01.contoso.com'
            Database           = 'CMDB'
            ComputerSearchRoot = 'OU=Computers,DC=contoso,DC=com'
            RecoverySearchRoot = 'DC=contoso,DC=com'
        }

        # Runs the whole script as a console would (errors non-terminating) and returns its
        # exit code and error records.
        function Invoke-ScriptUnderTest {
            $ErrorActionPreference = 'Continue'
            $global:LASTEXITCODE = 0
            $Output = & $script:ScriptPath @script:RunParameters 2>&1
            [pscustomobject]@{
                ExitCode = $LASTEXITCODE
                Errors   = @($Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            }
        }
    }

    BeforeEach {
        Mock Clear-Host {}
        Mock Write-Host {}
        Mock Start-Sleep {}
        Mock New-Item {}
        Mock Export-Csv {}
    }

    Context 'SQL' {
        BeforeEach {
            # Mock bodies and script methods run inside the script under test, where $script:
            # is that script's scope, so the fake's state lives in a global removed afterwards.
            $global:BlcTestSql = @{ Disposed = $false }
            Mock New-ComplianceSqlConnection {
                $Fake = New-Object PSObject
                $Fake | Add-Member -MemberType ScriptMethod -Name Open -Value {
                    throw (New-Object System.InvalidOperationException -ArgumentList 'simulated connection failure')
                }
                $Fake | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $global:BlcTestSql.Disposed = $true }
                $Fake
            }
        }

        AfterEach {
            Remove-Variable -Name BlcTestSql -Scope Global -ErrorAction SilentlyContinue
        }

        It 'exits with code 1 and writes no CSV when the connection cannot open' {
            $Result = Invoke-ScriptUnderTest
            $Result.ExitCode | Should -Be 1
            $Result.Errors.Count | Should -Be 1
            $Result.Errors[0].ToString() | Should -Match 'SQL query failed: .*simulated connection failure'
            Should -Invoke Export-Csv -Times 0 -Exactly
        }

        It 'disposes the connection' {
            $null = Invoke-ScriptUnderTest
            $global:BlcTestSql.Disposed | Should -BeTrue
        }
    }

    Context 'Active Directory' {
        BeforeEach {
            Mock New-ComplianceSqlConnection { New-Object PSObject }
            Mock Invoke-ComplianceQuery {
                $DataSet = New-Object System.Data.DataSet
                [void]$DataSet.Tables.Add('Altiris')
                $DataSet
            }
        }

        It 'exits with code 1 and writes no CSV when a computer search fails' {
            Mock New-ComplianceAdSearcher { New-FakeSearcher -Failure 'Access is denied.' }
            $Result = Invoke-ScriptUnderTest
            $Result.ExitCode | Should -Be 1
            $Result.Errors.Count | Should -Be 1
            $Result.Errors[0].ToString() | Should -Match "AD query failed: AD search of 'OU=Computers,DC=contoso,DC=com' failed: .*Access is denied"
            Should -Invoke Export-Csv -Times 0 -Exactly
        }

        It 'exits with code 1 and writes no CSV when the recovery-information search fails' {
            Mock New-ComplianceAdSearcher { New-FakeSearcher -Result (New-FakeComputer -Name 'PC01') } -ParameterFilter { $Filter -eq '(ObjectCategory=Computer)' }
            Mock New-ComplianceAdSearcher { New-FakeSearcher -Failure 'Access is denied.' } -ParameterFilter { $Filter -eq '(ObjectCategory=msFVE-RecoveryInformation)' }
            $Result = Invoke-ScriptUnderTest
            $Result.ExitCode | Should -Be 1
            $Result.Errors.Count | Should -Be 1
            $Result.Errors[0].ToString() | Should -Match "AD query failed: AD search of 'DC=contoso,DC=com' failed: .*Access is denied"
            Should -Invoke Export-Csv -Times 0 -Exactly
        }
    }
}

# The script must never read BitLocker recovery passwords (#110), so its CSVs cannot hold one.
Describe 'Get-BitlockerCompliance.ps1 recovery keys' {
    BeforeAll {
        $script:ScriptPath = Resolve-ScriptUnderTest -Name $PSCommandPath
    }

    It 'names msFVE-RecoveryPassword nowhere in its code' {
        $Tokens = $null
        $ParseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$Tokens, [ref]$ParseErrors)
        $Code = @($Tokens | Where-Object { $_.Kind -ne 'Comment' } | ForEach-Object { $_.Text })
        $Code | Where-Object { $_ -match 'msfve-recoverypassword' } | Should -BeNullOrEmpty
    }

    # Runs the whole script, as the failure tests above do, with every effect mocked: CSV
    # export, C:\Temp creation, Excel, console clearing and sleeps.
    Context 'when AD returns recovery passwords anyway' {
        BeforeAll {
            $script:RunParameters = @{
                ServerInstance     = 'sql01.contoso.com'
                Database           = 'CMDB'
                ComputerSearchRoot = 'OU=Computers,DC=contoso,DC=com'
                RecoverySearchRoot = 'DC=contoso,DC=com'
            }
            # Distinctive fake recovery password, built at runtime; not a real key.
            $script:FakeKey = @('111111', '222222', '333333', '444444', '555555', '666666', '777777', '888888') -join '-'
            $script:KeyId = '0A1B2C3D-0000-4000-8000-000000000001'

            $global:BlcTestFakeKey = $script:FakeKey
            $global:BlcTestKeyId = $script:KeyId
            $global:BlcTestCsv = New-Object System.Collections.ArrayList

            Mock Clear-Host {}
            Mock Write-Host {}
            Mock Start-Sleep {}
            Mock New-Item {}
            Mock Export-Csv { [void]$global:BlcTestCsv.Add([pscustomobject]@{ Path = $Path; Row = $InputObject }) }
            # New-Object has no -ComObject parameter off Windows, so Pester cannot mock it
            # there. This global shim, found before the cmdlet, returns a fake Excel for
            # -ComObject and hands every other call to the real cmdlet.
            function global:New-Object {
                param ([Parameter(Position = 0)][string]$TypeName, [Parameter(Position = 1)][object[]]$ArgumentList, [System.Collections.IDictionary]$Property, [string]$ComObject)
                if (-not $ComObject) { return Microsoft.PowerShell.Utility\New-Object @PSBoundParameters }
                $Sheet = Microsoft.PowerShell.Utility\New-Object PSObject
                $Sheet | Add-Member -MemberType ScriptMethod -Name Move -Value { param($Before) }
                $Book = Microsoft.PowerShell.Utility\New-Object PSObject
                $Book | Add-Member -MemberType NoteProperty -Name ActiveSheet -Value $Sheet
                $Books = Microsoft.PowerShell.Utility\New-Object PSObject
                $Books | Add-Member -MemberType NoteProperty -Name Book -Value $Book
                $Books | Add-Member -MemberType ScriptMethod -Name Open -Value { param($File) $this.Book }
                $Excel = Microsoft.PowerShell.Utility\New-Object PSObject
                $Excel | Add-Member -MemberType NoteProperty -Name Visible -Value $false
                $Excel | Add-Member -MemberType NoteProperty -Name Workbooks -Value $Books
                $Excel
            }
            Mock New-ComplianceSqlConnection { New-Object PSObject }
            Mock Invoke-ComplianceQuery {
                $DataSet = New-Object System.Data.DataSet
                $Table = $DataSet.Tables.Add('Altiris')
                [void]$Table.Columns.Add('Computer Name')
                [void]$Table.Columns.Add('Encryption Status')
                [void]$Table.Rows.Add('PC01', 'Bitlocker: Protected')
                [void]$Table.Rows.Add('PC03', 'Bitlocker: Fully Decrypted')
                [void]$Table.Rows.Add('PC09', 'Bitlocker: Protected')
                $DataSet
            }
            Mock New-ComplianceAdSearcher -ParameterFilter { $Filter -eq '(ObjectCategory=Computer)' } {
                New-FakeSearcher -Result (New-FakeComputer -Name 'PC01'), (New-FakeComputer -Name 'PC02'), (New-FakeComputer -Name 'PC03')
            }
            Mock New-ComplianceAdSearcher -ParameterFilter { $Filter -eq '(ObjectCategory=msFVE-RecoveryInformation)' } {
                $Recovery = foreach ($Computer in 'PC01', 'PC02', 'PC03') {
                    # One-element collections, like a real ADSI SearchResult, so the adspath
                    # Split runs through member enumeration exactly as it does against AD.
                    [pscustomobject]@{
                        Properties = @{
                            adspath                  = @("LDAP://CN=2020-01-02T10:00:00-08:00{$global:BlcTestKeyId},CN=$Computer,OU=Computers,DC=contoso,DC=com")
                            name                     = @("2020-01-02T10:00:00-08:00{$global:BlcTestKeyId}")
                            whencreated              = @([datetime]'2020-01-02')
                            'msfve-recoverypassword' = @($global:BlcTestFakeKey)
                        }
                    }
                }
                New-FakeSearcher -Result $Recovery
            }

            $ErrorActionPreference = 'Continue'
            # 3>$null drops the obsolete -NoTypeInformation warning that the Export-Csv mock repeats.
            $script:Output = & $script:ScriptPath @script:RunParameters 2>&1 3>$null
            $script:Rows = @($global:BlcTestCsv | ForEach-Object { $_.Row })
        }

        AfterAll {
            Remove-Variable -Name BlcTestCsv, BlcTestFakeKey, BlcTestKeyId -Scope Global -ErrorAction SilentlyContinue
            # Not Function:\global:New-Object: the Function: drive takes no scope prefix, so that
            # path never matches and the shim would leak into later test files (the MsiTools
            # real-COM tests then got the fake Excel instead of a WindowsInstaller object).
            Remove-Item -LiteralPath Function:\New-Object
        }

        It 'runs without errors and writes the four reports' {
            @($script:Output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) | Should -BeNullOrEmpty
            # One row reaches each report, so each report is checked below.
            @($global:BlcTestCsv | ForEach-Object { Split-Path -Path $_.Path -Leaf } | Sort-Object -Unique) |
                Should -Be @('ENCRYPTED.csv', 'IN AD NOT ALTIRIS.csv', 'IN ALTIRIS NOT AD.csv', 'VULNERABLE.csv')
            $script:Rows.Count | Should -Be 4
        }

        It 'never asks AD for msFVE-RecoveryPassword' {
            Should -Invoke New-ComplianceAdSearcher -Times 1 -Exactly -Scope Context -ParameterFilter { $Filter -eq '(ObjectCategory=msFVE-RecoveryInformation)' }
            Should -Invoke New-ComplianceAdSearcher -Times 0 -Exactly -Scope Context -ParameterFilter { $Property -contains 'msFVE-RecoveryPassword' }
        }

        It 'writes no BL_PW column' {
            foreach ($Row in $script:Rows) {
                $Row.PSObject.Properties.Name | Should -Not -Contain 'BL_PW'
            }
        }

        It 'writes the recovery key ID, never the recovery key' {
            ($script:Rows | Where-Object { $_.AD_Name -eq 'PC01' }).BL_PW_ID | Should -Be "{$script:KeyId}"
            foreach ($Row in $script:Rows) {
                foreach ($Value in $Row.PSObject.Properties.Value) {
                    "$Value" | Should -Not -Match ([regex]::Escape($script:FakeKey))
                }
            }
        }

        It 'writes exactly the columns the help describes' {
            $Expected = 'AD_Name', 'AD_Created', 'AD_Changed', 'BL_Name', 'BL_Created_Date', 'BL_Key_Count', 'BL_PW_ID',
                'ALT_Name', 'ALT_PC_Loc', 'ALT_User_Loc', 'ALT_Managed', 'ALT_OS_Name', 'ALT_ENC_Stat', 'ALT_ENC_Perc',
                'ALT_User_ID', 'ALT_User_Name', 'ALT_BL_LastClientUpdate', 'ALT_BL_LastInvChange', 'ALT_LastPolicyRequest'
            foreach ($Row in $script:Rows) {
                $Row.PSObject.Properties.Name | Should -Be $Expected
            }
            $Help = Get-Content -Path $script:ScriptPath -Raw
            foreach ($Column in $Expected) {
                $Help | Should -Match ('(?m)^\s+' + [regex]::Escape($Column) + '\s')
            }
        }
    }
}

Describe 'Get-BitlockerCompliance test cleanup' {
    It 'leaves no New-Object shim behind for later test files' {
        (Get-Command -Name New-Object).CommandType | Should -Be 'Cmdlet'
    }
}
