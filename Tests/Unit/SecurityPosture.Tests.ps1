#Requires -Version 5.1
# Behavior tests for Modules/SecurityPosture. The module is imported (it only defines functions);
# every CIM call goes through a Private helper that is mocked, so these run on any OS.

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'Modules/SecurityPosture/SecurityPosture.psd1') -Force
}

AfterAll {
    Remove-Module -Name SecurityPosture -Force -ErrorAction SilentlyContinue
}

Describe 'Get-DeviceGuardSecurityProperty' {
    BeforeEach {
        Mock Get-SecurityPostureOSVersion -ModuleName SecurityPosture { [version]'10.0.19045' }
        # Available holds values 2, 3 and 5 (three elements); Required holds 1 and 6. The old
        # scripts set the first N flags for an N-element array, so the values are chosen so
        # that index presence and value membership disagree.
        Mock Get-DeviceGuardInstance -ModuleName SecurityPosture {
            [pscustomobject]@{
                AvailableSecurityProperties = [uint32[]]@(2, 3, 5)
                RequiredSecurityProperties  = [uint32[]]@(1, 6)
            }
        }
    }

    It 'sets a flag when <Property>SecurityProperties holds its value' -ForEach @(
        @{ Property = 'Available'; Expected = 'False|True|True|False|True|False' }
        @{ Property = 'Required'; Expected = 'True|False|False|False|False|True' }
    ) {
        Get-DeviceGuardSecurityProperty -Property $Property -AsString | Should -Be $Expected
    }

    It 'returns an object with one Boolean per property, in the documented order' {
        $result = Get-DeviceGuardSecurityProperty -Property Available
        @($result.PSObject.Properties.Name) | Should -Be @('Hypervisor', 'SecureBoot', 'DmaProtection', 'SecureMemoryOverwrite', 'NxProtections', 'SmmMitigations')
        $result.Hypervisor | Should -BeFalse
        $result.SecureBoot | Should -BeTrue
        $result.DmaProtection | Should -BeTrue
        $result.SecureMemoryOverwrite | Should -BeFalse
        $result.NxProtections | Should -BeTrue
        $result.SmmMitigations | Should -BeFalse
        $result.SecureBoot | Should -BeOfType [bool]
    }

    It 'keeps the six-flag line when the array also holds 7 (MBEC/GMET) or 8 (APIC Virtualization)' {
        Mock Get-DeviceGuardInstance -ModuleName SecurityPosture {
            [pscustomobject]@{ AvailableSecurityProperties = [uint32[]]@(1, 7, 8); RequiredSecurityProperties = [uint32[]]@(7) }
        }
        Get-DeviceGuardSecurityProperty -Property Available -AsString | Should -Be 'True|False|False|False|False|False'
        Get-DeviceGuardSecurityProperty -Property Required -AsString | Should -Be 'False|False|False|False|False|False'
    }

    It 'returns all False when the array is empty or holds only 0 (None)' {
        Mock Get-DeviceGuardInstance -ModuleName SecurityPosture {
            [pscustomobject]@{ AvailableSecurityProperties = [uint32[]]@(0); RequiredSecurityProperties = $null }
        }
        Get-DeviceGuardSecurityProperty -Property Available -AsString | Should -Be 'False|False|False|False|False|False'
        Get-DeviceGuardSecurityProperty -Property Required -AsString | Should -Be 'False|False|False|False|False|False'
    }

    It 'returns N/A with -AsString before Windows 10 and does not read Win32_DeviceGuard' {
        Mock Get-SecurityPostureOSVersion -ModuleName SecurityPosture { [version]'6.3.9600' }
        Get-DeviceGuardSecurityProperty -Property Available -AsString | Should -Be 'N/A'
        Should -Invoke Get-DeviceGuardInstance -ModuleName SecurityPosture -Times 0 -Exactly
    }

    It 'warns and returns nothing without -AsString before Windows 10' {
        Mock Get-SecurityPostureOSVersion -ModuleName SecurityPosture { [version]'6.1.7601' }
        $result = Get-DeviceGuardSecurityProperty -Property Required -WarningVariable warnings -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        $warnings | Should -HaveCount 1
        "$warnings" | Should -Match 'Windows 10'
    }

    It 'writes a non-terminating error when Win32_DeviceGuard cannot be read' {
        Mock Get-DeviceGuardInstance -ModuleName SecurityPosture { throw 'Invalid namespace' }
        $result = Get-DeviceGuardSecurityProperty -Property Available -ErrorVariable errs -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$($errs[-1])" | Should -Match 'Win32_DeviceGuard.*Invalid namespace'
    }

    It 'writes a non-terminating error when the OS version cannot be read' {
        Mock Get-SecurityPostureOSVersion -ModuleName SecurityPosture { throw 'RPC unavailable' }
        $result = Get-DeviceGuardSecurityProperty -Property Available -ErrorVariable errs -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$($errs[-1])" | Should -Match 'operating system version.*RPC unavailable'
    }

    It 'rejects a -Property value other than Available or Required' {
        { Get-DeviceGuardSecurityProperty -Property Configured } | Should -Throw
    }
}

Describe 'Get-DeviceGuardStatus' {
    BeforeEach {
        Mock Get-DeviceGuardInstance -ModuleName SecurityPosture {
            [pscustomobject]@{
                AvailableSecurityProperties = [uint32[]]@(1, 2, 3)
                RequiredSecurityProperties  = [uint32[]]@(2, 9)
            }
        }
    }

    It 'translates each part from its own array' {
        $result = Get-DeviceGuardStatus
        $result.AvailableSecurityProperties | Should -Be @('Hypervisor', 'Secure Boot', 'DMA Protection')
        # The old script repeated the available loop's last name (DMA Protection) here.
        $result.RequiredSecurityProperties | Should -Be @('Secure Boot', 'Unknown (9)')
    }

    It 'returns the legacy line with -AsString' {
        Get-DeviceGuardStatus -AsString | Should -Be 'Hypervisor Secure Boot DMA Protection|Secure Boot Unknown (9)'
    }

    It 'names every documented value, 0 to 8' {
        Mock Get-DeviceGuardInstance -ModuleName SecurityPosture {
            [pscustomobject]@{ AvailableSecurityProperties = [uint32[]]@(0, 1, 2, 3, 4, 5, 6, 7, 8); RequiredSecurityProperties = [uint32[]]@(7) }
        }
        $result = Get-DeviceGuardStatus
        $result.AvailableSecurityProperties | Should -Be @('None', 'Hypervisor', 'Secure Boot', 'DMA Protection', 'Secure Memory Overwrite', 'NX Protections', 'SMM Mitigations', 'MBEC/GMET', 'APIC Virtualization')
        $result.RequiredSecurityProperties | Should -Be @('MBEC/GMET')
        Get-DeviceGuardStatus -AsString | Should -Be 'None Hypervisor Secure Boot DMA Protection Secure Memory Overwrite NX Protections SMM Mitigations MBEC/GMET APIC Virtualization|MBEC/GMET'
    }

    It 'returns an empty required part when RequiredSecurityProperties is empty' {
        Mock Get-DeviceGuardInstance -ModuleName SecurityPosture {
            [pscustomobject]@{ AvailableSecurityProperties = [uint32[]]@(1); RequiredSecurityProperties = [uint32[]]@() }
        }
        (Get-DeviceGuardStatus).RequiredSecurityProperties | Should -BeNullOrEmpty
        Get-DeviceGuardStatus -AsString | Should -Be 'Hypervisor|'
    }

    It 'writes a non-terminating error when Win32_DeviceGuard cannot be read' {
        Mock Get-DeviceGuardInstance -ModuleName SecurityPosture { throw 'Invalid class' }
        $result = Get-DeviceGuardStatus -ErrorVariable errs -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$($errs[-1])" | Should -Match 'Win32_DeviceGuard.*Invalid class'
    }
}

Describe 'SecurityPosture CIM helpers' {
    BeforeAll {
        # Get-CimInstance is missing on non-Windows PowerShell; the stub lets Mock attach there.
        Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'TestHelpers.psm1') -Force
        Register-CommandStub -Name Get-CimInstance -Parameter ClassName, Namespace, Filter, ComputerName
    }

    AfterAll {
        Remove-CommandStub -Name Get-CimInstance
    }

    It 'Get-DeviceGuardInstance reads Win32_DeviceGuard from the DeviceGuard namespace' {
        Mock Get-CimInstance -ModuleName SecurityPosture { 'instance' }
        InModuleScope SecurityPosture { Get-DeviceGuardInstance } | Should -Be 'instance'
        Should -Invoke Get-CimInstance -ModuleName SecurityPosture -Times 1 -Exactly -ParameterFilter {
            $ClassName -eq 'Win32_DeviceGuard' -and $Namespace -eq 'root\Microsoft\Windows\DeviceGuard'
        }
    }

    It 'Get-SecurityPostureOSVersion returns Win32_OperatingSystem.Version as a System.Version' {
        Mock Get-CimInstance -ModuleName SecurityPosture { [pscustomobject]@{ Version = '10.0.22631' } }
        $version = InModuleScope SecurityPosture { Get-SecurityPostureOSVersion }
        $version | Should -BeOfType [version]
        $version | Should -Be ([version]'10.0.22631')
        Should -Invoke Get-CimInstance -ModuleName SecurityPosture -Times 1 -Exactly -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' }
    }
}
