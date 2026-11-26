BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    $script:ScriptPath = Resolve-ScriptUnderTest -Name $PSCommandPath
    . (Get-ScriptFunctionDefinition -Path $script:ScriptPath)

    # SHA256 of the three bytes 'abc' (FIPS 180-2 test vector).
    $script:AbcSha256 = 'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD'
    function New-AbcFile {
        param([string]$Name)
        $Path = Join-Path $TestDrive $Name
        [System.IO.File]::WriteAllBytes($Path, [byte[]](0x61, 0x62, 0x63))
        $Path
    }
}

Describe 'ConvertFrom-TaniumUrlEncoding' {
    It 'decodes percent escapes and + as a space' {
        ConvertFrom-TaniumUrlEncoding -Value 'C%3A%5CProgram+Files%5Capp.exe' | Should -Be 'C:\Program Files\app.exe'
    }

    It 'keeps an encoded plus sign as a plus' {
        ConvertFrom-TaniumUrlEncoding -Value 'a%2Bb' | Should -Be 'a+b'
    }

    It 'leaves a plain path unchanged' {
        ConvertFrom-TaniumUrlEncoding -Value 'C:\Temp\file.txt' | Should -Be 'C:\Temp\file.txt'
    }
}

Describe 'Resolve-NativeFilePath' {
    It 'reads System32 through Sysnative from a 32-bit host on 64-bit Windows' {
        Resolve-NativeFilePath -Path 'c:\windows\system32\drivers\etc\hosts' -WindowsDirectory 'C:\Windows' -Wow64 $true |
            Should -Be 'C:\Windows\Sysnative\drivers\etc\hosts'
    }

    It 'leaves the path alone in a native host' {
        Resolve-NativeFilePath -Path 'C:\Windows\System32\kernel32.dll' -WindowsDirectory 'C:\Windows' -Wow64 $false |
            Should -Be 'C:\Windows\System32\kernel32.dll'
    }

    It 'leaves paths outside System32 alone' {
        Resolve-NativeFilePath -Path 'C:\Windows\System32Extra\a.dll' -WindowsDirectory 'C:\Windows' -Wow64 $true |
            Should -Be 'C:\Windows\System32Extra\a.dll'
        Resolve-NativeFilePath -Path 'D:\Data\a.txt' -WindowsDirectory 'C:\Windows' -Wow64 $true |
            Should -Be 'D:\Data\a.txt'
    }

    It 'reads <Path> through Sysnative from a 32-bit host' -TestCases @(
        @{ Path = 'C:/Windows/System32/notepad.exe' }
        @{ Path = '\\?\C:\Windows\System32\notepad.exe' }
        @{ Path = '\\?\C:/Windows/System32/notepad.exe' }
    ) {
        Resolve-NativeFilePath -Path $Path -WindowsDirectory 'C:\Windows' -Wow64 $true |
            Should -Be 'C:\Windows\Sysnative\notepad.exe'
    }

    It 'returns a non-System32 path with a long-path prefix unchanged' {
        Resolve-NativeFilePath -Path '\\?\D:\Data\a.txt' -WindowsDirectory 'C:\Windows' -Wow64 $true |
            Should -Be '\\?\D:\Data\a.txt'
    }
}

Describe 'Get-TaniumFileHash' {
    It 'outputs the hash of the decoded path' {
        $Path = New-AbcFile -Name 'abc file.txt'

        Get-TaniumFileHash -EncodedPath ([uri]::EscapeDataString($Path)) -HashType SHA256 | Should -Be $script:AbcSha256
    }

    It 'treats wildcard characters in the path literally' {
        $Path = New-AbcFile -Name 'abc[1].txt'

        Get-TaniumFileHash -EncodedPath ([uri]::EscapeDataString($Path)) -HashType MD5 | Should -Be '900150983CD24FB0D6963F7D28E17F72'
    }

    It 'writes an error and no hash when the path does not exist' {
        $Out = Get-TaniumFileHash -EncodedPath ([uri]::EscapeDataString((Join-Path $TestDrive 'missing.txt'))) -HashType SHA256 -ErrorAction SilentlyContinue -ErrorVariable Failure

        $Out | Should -BeNullOrEmpty
        "$Failure" | Should -Be 'Could not get the file hash'
    }

    It 'hashes a System32 path through Sysnative from a 32-bit host on 64-bit Windows' {
        $SavedArch = $env:PROCESSOR_ARCHITEW6432
        $SavedWindir = $env:WINDIR
        try {
            $env:PROCESSOR_ARCHITEW6432 = 'AMD64'
            $env:WINDIR = 'C:\Windows'
            Mock Test-Path { $true }
            Mock Get-FileHash { [pscustomobject]@{ Hash = 'FEEDFACE' } }

            Get-TaniumFileHash -EncodedPath ([uri]::EscapeDataString('C:\Windows\System32\notepad.exe')) -HashType SHA256 | Should -Be 'FEEDFACE'
            Should -Invoke Test-Path -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq 'C:\Windows\Sysnative\notepad.exe' }
            Should -Invoke Get-FileHash -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq 'C:\Windows\Sysnative\notepad.exe' -and $Algorithm -eq 'SHA256' }
        }
        finally {
            $env:PROCESSOR_ARCHITEW6432 = $SavedArch
            $env:WINDIR = $SavedWindir
        }
    }
}

Describe 'TaniumFileHash-Package.ps1' {
    BeforeAll {
        $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$null)
        $script:Strings = @($script:Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst] }, $true) | ForEach-Object { $_.Value })
    }

    It 'never launches powershell.exe or another PowerShell' {
        $Names = @($script:Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() })
        $Names + $script:Strings | Where-Object { $_ -match 'powershell(\.exe)?$|pwsh|EncodedCommand' } | Should -BeNullOrEmpty
        @($script:Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.InvocationOperator -ne 'Unknown' }, $true)) | Should -BeNullOrEmpty
    }

    It 'exits 1 when the hash call writes an error' {
        $TopLevel = @($script:Ast.EndBlock.Statements | Where-Object { $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst] })
        $Call = @($TopLevel | ForEach-Object { $_.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Get-TaniumFileHash' }, $true) })
        $Call.Count | Should -Be 1
        $ErrorVariable = @($Call[0].CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'ErrorVariable' })
        $ErrorVariable.Count | Should -Be 1
        $VariableName = $Call[0].CommandElements[$Call[0].CommandElements.IndexOf($ErrorVariable[0]) + 1].Value

        $Guard = @($TopLevel | Where-Object { $_ -is [System.Management.Automation.Language.IfStatementAst] })
        $Guard.Count | Should -Be 1
        $Guard[0].Clauses[0].Item1.Extent.Text | Should -Be "`$$VariableName"
        $Exit = @($Guard[0].Clauses[0].Item2.FindAll({ param($n) $n -is [System.Management.Automation.Language.ExitStatementAst] }, $true))
        $Exit.Count | Should -Be 1
        $Exit[0].Pipeline.Extent.Text | Should -Be '1'
    }

    It 'does not load System.Web' {
        $script:Ast.Extent.Text | Should -Not -Match 'LoadWithPartialName|System\.Web'
    }
}
