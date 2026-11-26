BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    $script:ScriptPath = Resolve-ScriptUnderTest -Name $PSCommandPath
    . (Get-ScriptFunctionDefinition -Path $script:ScriptPath)
}

Describe 'StartWPRSession-Sensor.ps1' {
    It 'is an advanced script, so -Verbose is a real parameter' {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$tokens, [ref]$errors)
        $attributes = @($ast.ParamBlock.Attributes | ForEach-Object { $_.TypeName.Name })
        $attributes | Should -Contain 'CmdletBinding'
    }
}

Describe 'ConvertTo-Seconds' {
    It 'converts <Duration> to <Expected> seconds' -ForEach @(
        @{ Duration = '5m'; Expected = 300 }
        @{ Duration = '300s'; Expected = 300 }
        @{ Duration = '2h'; Expected = 7200 }
        @{ Duration = '1h30m'; Expected = 5400 }
        @{ Duration = '1h30m15s'; Expected = 5415 }
        @{ Duration = '10m30s'; Expected = 630 }
        @{ Duration = '1H 5M'; Expected = 3900 }
        @{ Duration = '5min'; Expected = 300 }
        @{ Duration = '5mins'; Expected = 300 }
        @{ Duration = '10minutes'; Expected = 600 }
        @{ Duration = '1minute'; Expected = 60 }
        @{ Duration = '30sec'; Expected = 30 }
        @{ Duration = '30secs'; Expected = 30 }
        @{ Duration = '45seconds'; Expected = 45 }
        @{ Duration = '1hr'; Expected = 3600 }
        @{ Duration = '2hrs'; Expected = 7200 }
        @{ Duration = '1hour'; Expected = 3600 }
        @{ Duration = '2hours'; Expected = 7200 }
        @{ Duration = '1 hour 30 min'; Expected = 5400 }
        @{ Duration = '1HR30MIN15SEC'; Expected = 5415 }
    ) {
        ConvertTo-Seconds -InputDuration $Duration | Should -Be $Expected
    }

    It 'rejects <Duration>' -ForEach @(
        @{ Duration = 'soon' }
        @{ Duration = '90' }
        @{ Duration = 'x5m' }
        @{ Duration = '' }
        @{ Duration = '1.5h' }
        @{ Duration = '-5m' }
        @{ Duration = '5' }
        @{ Duration = '1h30' }
        @{ Duration = '5ms' }
        @{ Duration = '5mx' }
        @{ Duration = '5 minutesx' }
        @{ Duration = 'PT5M' }
    ) {
        { ConvertTo-Seconds -InputDuration $Duration } | Should -Throw '*Invalid duration format*'
    }
}

Describe 'InvokeWPRSession' {
    BeforeEach {
        Mock Start-Process { [pscustomobject]@{ Id = 42; HasExited = $true; ExitCode = 0 } }
        # Invoke-Wpr returns the wpr.exe exit code.
        Mock Invoke-Wpr { 0 }
    }

    It 'starts the profile at Light level and stops into the output file' {
        Mock Start-Sleep { }
        $output = InvokeWPRSession -WprProfile 'CPU' -OutputFile 'C:\ETLs\pc.etl' -Seconds 5
        $output | Should -Contain 'ETL file saved to C:\ETLs\pc.etl.'
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $ArgumentList -eq '-start CPU.light -filemode' -and $Wait }
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 5 }
        Should -Invoke Invoke-Wpr -Times 1 -Exactly -ParameterFilter { $ArgumentList[0] -eq '-stop' -and $ArgumentList[1] -eq 'C:\ETLs\pc.etl' }
        Should -Invoke Invoke-Wpr -Times 0 -Exactly -ParameterFilter { $ArgumentList -contains '-cancel' }
    }

    It 'records at Verbose level when verbose output is on' {
        Mock Start-Sleep { }
        $VerbosePreference = 'Continue'
        $null = InvokeWPRSession -WprProfile 'CPU' -OutputFile 'C:\ETLs\pc.etl' -Seconds 5 4>$null
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $ArgumentList -eq '-start CPU.verbose -filemode' }
    }

    It 'cancels the trace when stopped during the recording' {
        # A throw from Start-Sleep stands in for Ctrl+C or a stopped pipeline mid-sleep.
        Mock Start-Sleep { throw 'stopped' }
        { InvokeWPRSession -WprProfile 'CPU' -OutputFile 'C:\ETLs\pc.etl' -Seconds 5 } | Should -Throw 'stopped'
        Should -Invoke Invoke-Wpr -Times 1 -Exactly -ParameterFilter { $ArgumentList -contains '-cancel' }
        Should -Invoke Invoke-Wpr -Times 0 -Exactly -ParameterFilter { $ArgumentList -contains '-stop' }
    }

    It 'leaves the trace alone when wpr -start fails' {
        # For example, another WPR trace is already running: stopping or cancelling would act on it.
        Mock Start-Process { [pscustomobject]@{ Id = 42; HasExited = $true; ExitCode = -984076288 } }
        Mock Start-Sleep { }
        { InvokeWPRSession -WprProfile 'CPU' -OutputFile 'C:\ETLs\pc.etl' -Seconds 5 } | Should -Throw '*-start CPU.light -filemode failed with exit code -984076288*'
        Should -Invoke Invoke-Wpr -Times 0 -Exactly
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }

    It 'cancels the trace and claims no ETL file when wpr -stop fails' {
        Mock Start-Sleep { }
        Mock Invoke-Wpr { 3 } -ParameterFilter { $ArgumentList -contains '-stop' }
        $script:output = @()
        { InvokeWPRSession -WprProfile 'CPU' -OutputFile 'C:\ETLs\pc.etl' -Seconds 5 | ForEach-Object { $script:output += $_ } } |
            Should -Throw '*wpr -stop C:\ETLs\pc.etl failed with exit code 3*'
        Should -Invoke Invoke-Wpr -Times 1 -Exactly -ParameterFilter { $ArgumentList -contains '-cancel' }
        $script:output | Should -Not -BeLike 'ETL file saved*'
        $script:output | Should -Not -BeLike 'WPR recording has stopped*'
    }

    It 'warns when wpr -cancel fails' {
        Mock Start-Sleep { throw 'stopped' }
        Mock Invoke-Wpr { 1 } -ParameterFilter { $ArgumentList -contains '-cancel' }
        Mock Write-Warning { }
        { InvokeWPRSession -WprProfile 'CPU' -OutputFile 'C:\ETLs\pc.etl' -Seconds 5 } | Should -Throw 'stopped'
        Should -Invoke Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -like 'wpr -cancel failed with exit code 1.*' }
    }

    It 'does not warn when wpr -cancel succeeds' {
        Mock Start-Sleep { throw 'stopped' }
        Mock Write-Warning { }
        { InvokeWPRSession -WprProfile 'CPU' -OutputFile 'C:\ETLs\pc.etl' -Seconds 5 } | Should -Throw 'stopped'
        Should -Invoke Write-Warning -Times 0 -Exactly
    }
}

Describe 'Invoke-WPRSensor' {
    BeforeAll {
        $script:SavedComputerName = $env:COMPUTERNAME
        $env:COMPUTERNAME = 'TESTPC'
    }

    AfterAll {
        $env:COMPUTERNAME = $script:SavedComputerName
    }

    It 'names the error log COMPUTERNAME_timestamp.log, even when the duration is invalid' {
        $folder = Join-Path $TestDrive 'invalid-duration'
        $null = New-Item -ItemType Directory -Path $folder
        $null = Invoke-WPRSensor -Duration 'soon' -WprProfile 'CPU' -OutputPath $folder -ErrorAction SilentlyContinue
        $logs = @(Get-ChildItem -LiteralPath $folder -Filter '*.log')
        $logs.Count | Should -Be 1
        $logs[0].Name | Should -Match '^TESTPC_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.log$'
        Get-Content -LiteralPath $logs[0].FullName | Should -BeLike 'Error: Invalid duration format*'
    }

    It 'writes the error to the error stream' {
        $folder = Join-Path $TestDrive 'error-stream'
        $null = New-Item -ItemType Directory -Path $folder
        # -ErrorAction Continue: the CI shell runs with $ErrorActionPreference = 'stop'.
        $output = Invoke-WPRSensor -Duration 'soon' -WprProfile 'CPU' -OutputPath $folder -ErrorAction Continue 2>&1
        $errors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
        $errors.Count | Should -Be 1
        "$($errors[0])" | Should -BeLike 'An error occurred: Invalid duration format*'
    }

    It 'writes and logs a failed wpr -start' {
        Mock Start-Process { [pscustomobject]@{ Id = 42; HasExited = $true; ExitCode = 5 } }
        Mock Start-Sleep { }
        Mock Invoke-Wpr { 0 }
        $folder = Join-Path $TestDrive 'start-failed'
        $null = New-Item -ItemType Directory -Path $folder
        $output = Invoke-WPRSensor -Duration '5m' -WprProfile 'CPU' -OutputPath $folder -ErrorAction Continue 2>&1
        $errors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
        $errors.Count | Should -Be 1
        "$($errors[0])" | Should -BeLike 'An error occurred: wpr -start CPU.light -filemode failed with exit code 5.'
        Get-Content -LiteralPath (Get-ChildItem -LiteralPath $folder -Filter '*.log').FullName | Should -Be 'Error: wpr -start CPU.light -filemode failed with exit code 5.'
        Should -Invoke Invoke-Wpr -Times 0 -Exactly
    }

    It 'writes, logs and claims no ETL file for a failed wpr -stop' {
        Mock Start-Process { [pscustomobject]@{ Id = 42; HasExited = $true; ExitCode = 0 } }
        Mock Start-Sleep { }
        Mock Invoke-Wpr { 0 }
        Mock Invoke-Wpr { 3 } -ParameterFilter { $ArgumentList -contains '-stop' }
        $folder = Join-Path $TestDrive 'stop-failed'
        $null = New-Item -ItemType Directory -Path $folder
        $output = Invoke-WPRSensor -Duration '5m' -WprProfile 'CPU' -OutputPath $folder -ErrorAction Continue 2>&1
        $errors = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
        $errors.Count | Should -Be 1
        "$($errors[0])" | Should -BeLike 'An error occurred: wpr -stop * failed with exit code 3.'
        @($output | Where-Object { $_ -is [string] -and $_ -like 'ETL file saved*' }).Count | Should -Be 0
        Get-Content -LiteralPath (Get-ChildItem -LiteralPath $folder -Filter '*.log').FullName | Should -BeLike 'Error: wpr -stop * failed with exit code 3.'
        Should -Invoke Invoke-Wpr -Times 1 -Exactly -ParameterFilter { $ArgumentList -contains '-cancel' }
    }

    It 'logs the error before a caller Stop preference terminates it' {
        $folder = Join-Path $TestDrive 'stop-preference'
        $null = New-Item -ItemType Directory -Path $folder
        { Invoke-WPRSensor -Duration 'soon' -WprProfile 'CPU' -OutputPath $folder -ErrorAction Stop } |
            Should -Throw 'An error occurred: Invalid duration format*'
        $logs = @(Get-ChildItem -LiteralPath $folder -Filter '*.log')
        $logs.Count | Should -Be 1
        Get-Content -LiteralPath $logs[0].FullName | Should -BeLike 'Error: Invalid duration format*'
    }

    It 'records for the parsed duration into COMPUTERNAME_timestamp.etl' {
        Mock InvokeWPRSession { }
        $null = Invoke-WPRSensor -Duration '1h30m' -WprProfile 'DiskIO' -OutputPath $TestDrive
        Should -Invoke InvokeWPRSession -Times 1 -Exactly -ParameterFilter {
            $Seconds -eq 5400 -and $WprProfile -eq 'DiskIO' -and (Split-Path -Leaf $OutputFile) -match '^TESTPC_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.etl$'
        }
    }
}
