#Requires -Version 5.1
# Tests for Analyze-HelpCoverage.ps1. Fixture scripts are written to $TestDrive and only parsed
# by the analyzer; the fixtures with top-level code write a marker file so the tests can prove
# that no fixture is ever executed.

BeforeAll {
    $script:analyzer = Join-Path (Split-Path -Parent $PSScriptRoot) 'Analyze-HelpCoverage.ps1'
    $script:fixtureRoot = Join-Path $TestDrive 'repo'
    $script:marker = Join-Path $TestDrive 'executed.txt'
    $scriptsDir = Join-Path $script:fixtureRoot 'Scripts/Fixture'
    New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null

    $functionHelp = @'
    <#
    .SYNOPSIS
        Returns a greeting.
    .DESCRIPTION
        Builds a greeting string for Name and writes it to the pipeline.
    .PARAMETER Name
        Who to greet.
    .EXAMPLE
        Get-Greeting -Name World
    .EXAMPLE
        'World' | ForEach-Object { Get-Greeting -Name $_ }
__NOTES__
    #>
'@
    $libraryTemplate = @'
function Get-Greeting {
__HELP__
    param([string]$Name)
    "Hello, $Name"
}
'@
    $notes = "    .NOTES`n        None."

    $runsCode = "Set-Content -Path '$($script:marker)' -Value 'ran'"
    $complete = $libraryTemplate.Replace('__HELP__', $functionHelp.Replace('__NOTES__', $notes))
    $noNotes = $libraryTemplate.Replace('__HELP__', $functionHelp.Replace('__NOTES__', ''))
    $noHelp = "$runsCode`nGet-Date"
    # A documented function plus top-level code: running the script does something its function
    # help does not describe, so it must be graded at script level.
    $mixed = $complete + "`n$runsCode`nGet-Greeting -Name World`n"
    $namedBlocks = "begin { `$x = 1 }`nend {`n" + $complete + "}`n"
    $twoFunctions = $complete + "`n`nfunction Get-Farewell {`n    param([string]`$Name)`n    `"Bye, `$Name`"`n}`n"
    $scriptParams = "param([string]`$Path)`n`n" + $complete

    Set-Content -Path (Join-Path $scriptsDir 'Library-Complete.ps1') -Value $complete
    Set-Content -Path (Join-Path $scriptsDir 'Library-NoNotes.ps1') -Value $noNotes
    Set-Content -Path (Join-Path $scriptsDir 'Script-NoHelp.ps1') -Value $noHelp
    Set-Content -Path (Join-Path $scriptsDir 'Library-TwoFunctions.ps1') -Value $twoFunctions
    Set-Content -Path (Join-Path $scriptsDir 'Script-ParamsNoHelp.ps1') -Value $scriptParams
    Set-Content -Path (Join-Path $scriptsDir 'Script-FunctionAndCode.ps1') -Value $mixed
    Set-Content -Path (Join-Path $scriptsDir 'Script-NamedBlocks.ps1') -Value $namedBlocks

    # Module function files (Modules/<Name>/Public and Private): one function per file, help inside the body.
    $publicDir = Join-Path $script:fixtureRoot 'Modules/Foo/Public'
    $privateDir = Join-Path $script:fixtureRoot 'Modules/Foo/Private'
    New-Item -ItemType Directory -Path $publicDir, $privateDir -Force | Out-Null
    Set-Content -Path (Join-Path $publicDir 'Get-Foo.ps1') -Value $complete.Replace('Get-Greeting', 'Get-Foo')
    Set-Content -Path (Join-Path $privateDir 'Get-FooHelper.ps1') -Value "function Get-FooHelper {`n    'helper'`n}`n"

    $reportPath = Join-Path $TestDrive 'report.json'
    & $script:analyzer -RepoRoot $script:fixtureRoot -OutputPath $reportPath 6>$null | Out-Null
    $script:report = Get-Content -Path $reportPath -Raw | ConvertFrom-Json

    function Get-ReportItem([string]$Name) {
        if ($Name -notlike '*/*') { $Name = "Scripts/Fixture/$Name" }
        @($script:report.Items | Where-Object { $_.File -eq $Name })
    }
}

Describe 'Analyze-HelpCoverage.ps1' {
    It 'never executes a fixture script' {
        Test-Path -LiteralPath $script:marker | Should -BeFalse
    }

    It 'grades a compliant function-only script per function as Complete' {
        $items = Get-ReportItem 'Library-Complete.ps1'
        $items.Count | Should -Be 1
        $items[0].Function | Should -Be 'Get-Greeting'
        $items[0].Grade | Should -Be 'Complete'
    }

    It 'grades a function-only script missing .NOTES as Partial' {
        $items = Get-ReportItem 'Library-NoNotes.ps1'
        $items.Count | Should -Be 1
        $items[0].Function | Should -Be 'Get-Greeting'
        $items[0].Grade | Should -Be 'Partial'
        @($items[0].Missing) | Should -Be @('NOTES')
    }

    It 'grades a script with no help and no functions as None at script level' {
        $items = Get-ReportItem 'Script-NoHelp.ps1'
        $items.Count | Should -Be 1
        $items[0].Function | Should -BeNullOrEmpty
        $items[0].Grade | Should -Be 'None'
    }

    It 'grades every top-level function of a library separately' {
        $items = Get-ReportItem 'Library-TwoFunctions.ps1'
        ($items | Sort-Object Function | ForEach-Object { "$($_.Function)=$($_.Grade)" }) -join ',' |
            Should -Be 'Get-Farewell=None,Get-Greeting=Complete'
    }

    It 'grades a script with its own param() block at script level even when it defines functions' {
        $items = Get-ReportItem 'Script-ParamsNoHelp.ps1'
        $items.Count | Should -Be 1
        $items[0].Function | Should -BeNullOrEmpty
        $items[0].Grade | Should -Be 'None'
        @($items[0].Missing) | Should -Contain 'PARAMETER Path'
    }

    It 'grades a documented function plus top-level code as None at script level' {
        $items = Get-ReportItem 'Script-FunctionAndCode.ps1'
        $items.Count | Should -Be 1
        $items[0].Function | Should -BeNullOrEmpty
        $items[0].Grade | Should -Be 'None'
    }

    It 'says why a documented function plus top-level code is graded at script level' {
        $items = Get-ReportItem 'Script-FunctionAndCode.ps1'
        @($items[0].Missing)[0] | Should -Be 'top-level code outside functions; graded at script level'
    }

    It 'does not add the script-level reason for a plain script with no functions' {
        $items = Get-ReportItem 'Script-NoHelp.ps1'
        @($items[0].Missing) | Should -Not -Contain 'top-level code outside functions; graded at script level'
        @($items[0].Missing) | Should -Contain 'SYNOPSIS'
    }

    It 'grades a script with begin/end blocks at script level' {
        $items = Get-ReportItem 'Script-NamedBlocks.ps1'
        $items.Count | Should -Be 1
        $items[0].Function | Should -BeNullOrEmpty
        $items[0].Grade | Should -Be 'None'
    }

    It 'grades a Modules/Foo/Public function file per function as Complete' {
        $items = Get-ReportItem 'Modules/Foo/Public/Get-Foo.ps1'
        $items.Count | Should -Be 1
        $items[0].Function | Should -Be 'Get-Foo'
        $items[0].Grade | Should -Be 'Complete'
    }

    It 'grades a Modules/Foo/Private helper file too' {
        $items = Get-ReportItem 'Modules/Foo/Private/Get-FooHelper.ps1'
        $items.Count | Should -Be 1
        $items[0].Function | Should -Be 'Get-FooHelper'
        $items[0].Grade | Should -Be 'None'
    }

    It 'keeps the report shape' {
        $script:report.PSObject.Properties.Name | Should -Be @('Standard', 'FilesScanned', 'ItemsGraded', 'Complete', 'Partial', 'None', 'Items')
        $script:report.FilesScanned | Should -Be 9
        $script:report.ItemsGraded | Should -Be 10
    }
}
