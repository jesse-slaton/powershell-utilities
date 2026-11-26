BeforeDiscovery {
    # -Skip is read during discovery, before BeforeAll runs. $IsWindows does not exist on 5.1.
    $script:OnWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

BeforeAll {
    Import-Module "$PSScriptRoot/../TestHelpers.psm1" -Force
    $script:ScriptPath = Resolve-ScriptUnderTest -Name $PSCommandPath
    . (Get-ScriptFunctionDefinition -Path $script:ScriptPath)

    $script:Nominatim = [pscustomobject]@{
        address = [pscustomobject]@{ road = 'Pine Street'; city = 'Seattle'; state = 'Washington'; country_code = 'us' }
    }
}

Describe 'GetLocation.ps1' {
    It 'uses neither System.Device nor GeoCoordinateWatcher, which PowerShell 7 does not have' {
        $Tokens = $null
        $ParseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$Tokens, [ref]$ParseErrors)
        @($Tokens | Where-Object { $_.Kind -ne 'Comment' -and $_.Text -match 'System\.Device\b|GeoCoordinateWatcher' }) | Should -BeNullOrEmpty
    }

    It 'starts no other PowerShell' {
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$null)
        $Commands = @($Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() })
        $Commands | Where-Object { $_ -match '^(powershell|pwsh)(\.exe)?$|^Start-Process$|^Start-Job$' } | Should -BeNullOrEmpty
    }
}

Describe 'Initialize-GeolocatorInterop' {
    # Compiles the real C# helper with this PowerShell's compiler (C# 5 on Windows PowerShell
    # 5.1, Roslyn on PowerShell 7). Compiling calls nothing in Windows, so it runs everywhere.
    It 'compiles the WinRT Geolocator helper with GetPosition(int) and GetLocationStatus()' {
        Initialize-GeolocatorInterop
        $Type = 'PsuGeolocation.WinRtGeolocator' -as [type]
        $Type | Should -Not -BeNullOrEmpty
        $Method = $Type.GetMethod('GetPosition')
        $Method.ReturnType | Should -Be ([double[]])
        @($Method.GetParameters().ParameterType) | Should -Be @([int])
        $Status = $Type.GetMethod('GetLocationStatus')
        $Status.ReturnType | Should -Be ([int])
        @($Status.GetParameters()) | Should -BeNullOrEmpty
    }

    # Activates the real Geolocator and reads LocationStatus through the IGeolocator vtable,
    # so a wrong IID or slot layout fails here. It never asks for a position.
    It 'reads a PositionStatus (0-5) from the real Geolocator on Windows' -Skip:(-not $script:OnWindows) {
        Initialize-GeolocatorInterop
        $Type = 'PsuGeolocation.WinRtGeolocator' -as [type]
        try {
            $Status = $Type::GetLocationStatus()
        }
        catch {
            if ("$($_.Exception.InnerException.Message)" -match '0x80040154') {
                Set-ItResult -Skipped -Because 'the Geolocator class is not registered on this Windows edition (REGDB_E_CLASSNOTREG)'
                return
            }
            throw
        }
        $Status | Should -BeOfType ([int])
        $Status | Should -BeGreaterOrEqual 0
        $Status | Should -BeLessOrEqual 5
    }

    It 'is safe to call again once the type exists' {
        { Initialize-GeolocatorInterop; Initialize-GeolocatorInterop } | Should -Not -Throw
    }
}

Describe 'Get-DeviceCoordinate' {
    It 'returns the latitude and longitude from the Geolocator' {
        Mock Invoke-GeolocatorRequest { , [double[]]@(47.6062, -122.3321) }
        $Coordinate = Get-DeviceCoordinate -TimeoutSeconds 5
        $Coordinate.Latitude | Should -Be 47.6062
        $Coordinate.Longitude | Should -Be -122.3321
        Should -Invoke Invoke-GeolocatorRequest -Times 1 -Exactly -ParameterFilter { $TimeoutSeconds -eq 5 }
    }

    It 'stops with the real reason when location access is denied' {
        Mock Invoke-GeolocatorRequest {
            $Denied = New-Object System.UnauthorizedAccessException -ArgumentList 'Access to location is denied. Turn on location services and allow desktop apps to access your location.'
            throw (New-Object System.Management.Automation.MethodInvocationException -ArgumentList 'Exception calling "GetPosition"', $Denied)
        }
        { Get-DeviceCoordinate } | Should -Throw 'Location is unavailable: Access to location is denied.*'
    }

    It 'stops when the Geolocator times out' {
        Mock Invoke-GeolocatorRequest { throw (New-Object System.TimeoutException -ArgumentList 'The location service gave no position within 30 seconds.') }
        { Get-DeviceCoordinate } | Should -Throw 'Location is unavailable: The location service gave no position within 30 seconds.'
    }

    It 'stops instead of reporting coordinates the service did not give' {
        Mock Invoke-GeolocatorRequest { , [double[]]@([double]::NaN, [double]::NaN) }
        { Get-DeviceCoordinate } | Should -Throw 'Location is unavailable: the location service returned no valid coordinates*'
        Mock Invoke-GeolocatorRequest { }
        { Get-DeviceCoordinate } | Should -Throw 'Location is unavailable: the location service returned no valid coordinates*'
        Mock Invoke-GeolocatorRequest { , [double[]]@(91, 0) }
        { Get-DeviceCoordinate } | Should -Throw 'Location is unavailable: the location service returned no valid coordinates*'
    }

    # Runs the real helper. Off Windows combase.dll does not exist, so the call must fail loudly.
    # On Windows it would ask the real location service, so it is skipped there.
    It 'turns a failure inside the real Geolocator helper into a terminating error' -Skip:$script:OnWindows {
        { Get-DeviceCoordinate -TimeoutSeconds 1 } | Should -Throw 'Location is unavailable: *'
    }
}

Describe 'Get-DeviceLocationReport' {
    BeforeEach {
        Mock Get-DeviceCoordinate { [pscustomobject]@{ Latitude = 47.60621; Longitude = -122.33207 } }
        Mock Invoke-RestMethod { '203.0.113.7' } -ParameterFilter { $Uri -eq 'http://ifconfig.me/ip' }
        Mock Invoke-RestMethod { $script:Nominatim } -ParameterFilter { "$Uri" -like 'https://nominatim.openstreetmap.org/*' }
    }

    It 'writes road, city, state, country, rounded coordinates and public IP on one line' {
        Get-DeviceLocationReport | Should -BeExactly 'Pine Street|Seattle|Washington|us|47.61|-122.33|203.0.113.7'
    }

    It 'reverse-geocodes the full-precision coordinates' {
        $null = Get-DeviceLocationReport
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            "$Uri" -eq 'https://nominatim.openstreetmap.org/reverse?lat=47.60621&lon=-122.33207&format=jsonv2&addressdetails=1'
        }
    }

    It 'leaves fields the service does not return empty' {
        Mock Invoke-RestMethod { [pscustomobject]@{ address = [pscustomobject]@{ country_code = 'us' } } } -ParameterFilter { "$Uri" -like 'https://nominatim.openstreetmap.org/*' }
        Get-DeviceLocationReport | Should -BeExactly '|||us|47.61|-122.33|203.0.113.7'
    }

    It 'writes periods, not commas, in the URL and the line under a comma-decimal culture' {
        $Thread = [System.Threading.Thread]::CurrentThread
        $Saved = $Thread.CurrentCulture
        try {
            $Thread.CurrentCulture = New-Object System.Globalization.CultureInfo -ArgumentList 'de-DE'
            if ((1.5).ToString() -ne '1,5') {
                Set-ItResult -Skipped -Because 'this host has no de-DE culture data (invariant globalization)'
                return
            }
            $Line = Get-DeviceLocationReport
        }
        finally {
            $Thread.CurrentCulture = $Saved
        }
        $Line | Should -BeExactly 'Pine Street|Seattle|Washington|us|47.61|-122.33|203.0.113.7'
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { "$Uri" -like '*lat=47.60621&lon=-122.33207&*' }
    }

    It 'stops when location is unavailable, before any web request' {
        Mock Get-DeviceCoordinate { throw 'Location is unavailable: Access to location is denied.' }
        { Get-DeviceLocationReport } | Should -Throw 'Location is unavailable: *'
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }
}
