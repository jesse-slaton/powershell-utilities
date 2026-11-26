BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    Register-CommandStub -Name Get-CimInstance -Parameter Namespace, ClassName, Filter, ComputerName
    $script:ScriptPath = Resolve-ScriptUnderTest -Name $PSCommandPath
    . (Get-ScriptFunctionDefinition -Path $script:ScriptPath)

    # WARNING: this departs from the TestHelpers rule of never running a script's top-level
    # code. The script's WHOLE TEXT is wrapped in a function and called, so its param block,
    # begin and process blocks really execute here, to test parameter and pipeline handling
    # as a caller sees it. That is safe only because the script's top-level code just builds
    # a hashtable and reads WMI (mocked below). If side-effecting top-level code is ever added
    # to the script (writing files, the registry, network calls, anything not mocked here),
    # it WILL run during the tests: move that code into a function and mock it, or drop this
    # wrapper and test the functions via Get-ScriptFunctionDefinition only.
    $scriptText = [System.IO.File]::ReadAllText($script:ScriptPath)
    . ([scriptblock]::Create("function Invoke-MonitorScript {`n$scriptText`n}"))

    $script:MissingCsv = Join-Path $TestDrive 'no-such-file.csv'

    # Stands in for a CimException: a real one gets its NativeErrorCode from WMI and cannot
    # be built with a chosen code. The script reads only the NativeErrorCode property.
    if (-not ('TestCimLikeException' -as [type])) {
        Add-Type -TypeDefinition @'
public class TestCimLikeException : System.Exception {
    private readonly string code;
    public TestCimLikeException(string code, string message) : base(message) { this.code = code; }
    public string NativeErrorCode { get { return code; } }
}
'@
    }

    function ConvertTo-EdidBytes {
        param ([string]$Text)
        [byte[]][System.Text.Encoding]::ASCII.GetBytes($Text + [char]0)
    }

    # One monitor per computer; its serial number is the computer name, so results can be told apart.
    function Set-MonitorMock {
        Mock Get-CimInstance {
            $name = if ($ComputerName) { $ComputerName } else { 'LOCAL' }
            [pscustomobject]@{
                InstanceName           = "DISPLAY\HPN3401\$name"
                ManufacturerName       = ConvertTo-EdidBytes 'HPN'
                UserFriendlyName       = ConvertTo-EdidBytes 'HP E243i'
                UserFriendlyNameLength = 8
                SerialNumberID         = ConvertTo-EdidBytes $name
                WeekOfManufacture      = 29
                YearOfManufacture      = 2017
            }
        } -ParameterFilter { $ClassName -eq 'WMIMonitorID' }
        Mock Get-CimInstance { [pscustomobject]@{ MaxHorizontalImageSize = 52; MaxVerticalImageSize = 32 } } -ParameterFilter { $ClassName -eq 'WmiMonitorBasicDisplayParams' }
        Mock Get-CimInstance { [pscustomobject]@{ VideoOutputTechnology = 10 } } -ParameterFilter { $ClassName -eq 'WmiMonitorConnectionParams' }
        Mock Get-CimInstance {
            [pscustomobject]@{
                MonitorSourceModes = @(
                    [pscustomobject]@{ HorizontalActivePixels = 1280; VerticalActivePixels = 1024 }
                    [pscustomobject]@{ HorizontalActivePixels = 1920; VerticalActivePixels = 1200 }
                )
            }
        } -ParameterFilter { $ClassName -eq 'WmiMonitorListedSupportedSourceModes' }
    }
}

AfterAll {
    Remove-CommandStub -Name Get-CimInstance
}

Describe 'Get-AttachedMonitorInfo-Sensor.ps1' {
    BeforeEach {
        Set-MonitorMock
    }

    It 'queries every piped computer name' {
        $result = @('PC01', 'PC02', 'PC03' | Invoke-MonitorScript -ManufacturerCsvPath $script:MissingCsv)
        foreach ($name in 'PC01', 'PC02', 'PC03') {
            Should -Invoke Get-CimInstance -Times 1 -Exactly -ParameterFilter { $ClassName -eq 'WMIMonitorID' -and $ComputerName -eq $name }
        }
        @($result.SerialNumber) | Should -Be @('PC01', 'PC02', 'PC03')
        @($result.Computer) | Should -Be @('PC01', 'PC02', 'PC03')
    }

    It 'queries every name passed to -ComputerName, with a Computer property' {
        $result = @(Invoke-MonitorScript -ComputerName 'PC01', 'PC02' -ManufacturerCsvPath $script:MissingCsv)
        @($result.Computer) | Should -Be @('PC01', 'PC02')
    }

    It 'writes only monitor objects in Object format' {
        $result = @(Invoke-MonitorScript -ComputerName 'PC01', 'PC02' -ManufacturerCsvPath $script:MissingCsv)
        $result.Count | Should -Be 2
        @($result | Where-Object { $_ -is [string] }) | Should -BeNullOrEmpty
        $result[0].Manufacturer | Should -Be 'HP'
        $result[0].Model | Should -Be 'HP E243i'
        $result[0].Connection | Should -Be 'Displayport'
        $result[0].Size | Should -Be '24'
        $result[0].MaxResolution | Should -Be '1920x1200'
    }

    It 'reports a computer that cannot be queried and goes on with the next one' {
        # Get-CimInstance reports an unreachable computer as a non-terminating error.
        Mock Get-CimInstance { Write-Error 'The WinRM client cannot process the request.' } -ParameterFilter { $ClassName -eq 'WMIMonitorID' -and $ComputerName -eq 'BAD01' }
        $output = @('BAD01', 'PC02' | Invoke-MonitorScript -ManufacturerCsvPath $script:MissingCsv 2>&1)
        $errors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
        $objects = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
        $errors.Count | Should -Be 1
        "$($errors[0])" | Should -BeLike '*BAD01*WinRM client cannot process*'
        $errors[0].TargetObject | Should -Be 'BAD01'
        @($objects.SerialNumber) | Should -Be @('PC02')
    }

    It 'reports a query that throws' {
        Mock Get-CimInstance { throw 'Access denied.' } -ParameterFilter { $ClassName -eq 'WMIMonitorID' }
        $null = Get-MonitorInfo -Computer 'PC01' -ErrorAction SilentlyContinue -ErrorVariable failures
        "$(@($failures)[-1])" | Should -BeLike 'Cannot read monitor data from PC01: *Access denied.*'
    }

    It 'treats a NotSupported WMI error on <Computer> as no monitors' -ForEach @(
        @{ Computer = 'VM01' }
        @{ Computer = 'localhost' }
    ) {
        Mock Get-CimInstance { throw (New-Object TestCimLikeException 'NotSupported', 'Not supported') } -ParameterFilter { $ClassName -eq 'WMIMonitorID' }
        $output = @(Get-MonitorInfo -Computer $Computer -Verbose 2>&1 4>&1)
        @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) | Should -BeNullOrEmpty
        @($output | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] }) | Should -BeNullOrEmpty
        @($output | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and "$_" -like "No monitor data on ${Computer}:*not supported*" }).Count | Should -Be 1
    }

    It 'still reports a WMI error other than NotSupported' {
        Mock Get-CimInstance { throw (New-Object TestCimLikeException 'AccessDenied', 'Access denied') } -ParameterFilter { $ClassName -eq 'WMIMonitorID' }
        $output = @(Get-MonitorInfo -Computer 'PC01' 2>&1)
        $errors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
        $errors.Count | Should -Be 1
        "$($errors[0])" | Should -BeLike 'Cannot read monitor data from PC01: Access denied'
    }

    It 'goes on with the next piped computer after a NotSupported one' {
        Mock Get-CimInstance { throw (New-Object TestCimLikeException 'NotSupported', 'Not supported') } -ParameterFilter { $ClassName -eq 'WMIMonitorID' -and $ComputerName -eq 'VM01' }
        $output = @('VM01', 'PC02' | Invoke-MonitorScript -ManufacturerCsvPath $script:MissingCsv 2>&1)
        @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) | Should -BeNullOrEmpty
        @($output.SerialNumber) | Should -Be @('PC02')
    }
}

Describe 'Get-MonitorInfo' {
    BeforeEach {
        Set-MonitorMock
    }

    It 'leaves out the Computer property unless asked' {
        $result = Get-MonitorInfo -Computer 'PC01' -ManufacturerHash @{ HPN = 'HP' }
        $result.PSObject.Properties.Name | Should -Not -Contain 'Computer'
    }

    It 'queries the local computer without -ComputerName' {
        $null = Get-MonitorInfo -Computer 'localhost'
        Should -Invoke Get-CimInstance -Times 1 -Exactly -ParameterFilter { $ClassName -eq 'WMIMonitorID' -and -not $ComputerName }
    }

    It 'writes the PowerShell version only to the verbose stream' {
        $output = @(Get-MonitorInfo -Computer 'PC01' -Verbose 4>&1)
        @($output | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and "$_" -like 'Running PowerShell*' }).Count | Should -Be 1
        @($output | Where-Object { $_ -is [string] }) | Should -BeNullOrEmpty
    }

    It 'writes one pipe-delimited line per monitor in Delimited format' {
        Mock Write-Host { }
        $result = Get-MonitorInfo -Computer 'PC01' -OutputFormat Delimited -ManufacturerHash @{ HPN = 'HP' }
        $result | Should -BeNullOrEmpty
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { "$Object" -eq 'HP|HP E243i|PC01|29|2017|Displayport|24|1920x1200|DISPLAY\HPN3401\PC01' }
    }
}
