#Requires -Version 5.1
<#
.SYNOPSIS
    Fixture for TestHelpers.Tests.ps1. Never run it; its top-level code throws.

.DESCRIPTION
    The self-tests load these functions with Get-ScriptFunctionDefinition and check
    that coverage maps to the line numbers below. Moving a line here means updating
    the line numbers in TestHelpers.Tests.ps1.
#>

function Get-CoverageSampleSign {
    <#
    .SYNOPSIS
        Returns 'positive' or 'not positive' for a number.

    .PARAMETER Number
        The number to classify.

    .EXAMPLE
        Get-CoverageSampleSign -Number 3
    #>
    param([int]$Number)

    if ($Number -gt 0) {
        'positive'
    }
    else {
        'not positive'
    }
}

function Get-CoverageSampleGreeting($Name) {
    "hello $Name"
}

function Get-CoverageSampleReport {
    "report: $(Get-CoverageSampleGreeting 'team')"
}

throw 'CoverageSample.ps1 top-level code ran; tests must load only its functions.'
