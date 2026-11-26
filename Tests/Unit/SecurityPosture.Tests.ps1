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
        Mock Get-SecurityPostureOSVersion -ModuleName SecurityPosture { [version]'10.0.19045' }
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

    It 'returns N/A with -AsString before Windows 10 and does not read Win32_DeviceGuard' {
        Mock Get-SecurityPostureOSVersion -ModuleName SecurityPosture { [version]'6.3.9600' }
        Get-DeviceGuardStatus -AsString | Should -Be 'N/A'
        Should -Invoke Get-DeviceGuardInstance -ModuleName SecurityPosture -Times 0 -Exactly
    }

    It 'warns and returns nothing without -AsString before Windows 10' {
        Mock Get-SecurityPostureOSVersion -ModuleName SecurityPosture { [version]'6.1.7601' }
        $result = Get-DeviceGuardStatus -WarningVariable warnings -WarningAction SilentlyContinue -ErrorVariable errs -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        $errs | Should -BeNullOrEmpty
        $warnings | Should -HaveCount 1
        "$warnings" | Should -Match 'Windows 10'
        Should -Invoke Get-DeviceGuardInstance -ModuleName SecurityPosture -Times 0 -Exactly
    }

    It 'writes a non-terminating error when the OS version cannot be read' {
        Mock Get-SecurityPostureOSVersion -ModuleName SecurityPosture { throw 'RPC unavailable' }
        $result = Get-DeviceGuardStatus -ErrorVariable errs -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        "$($errs[-1])" | Should -Match 'operating system version.*RPC unavailable'
    }
}

Describe 'SecurityPosture CIM helpers' {
    BeforeAll {
        # Get-CimInstance is missing on non-Windows PowerShell; the stub lets Mock attach there.
        Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'TestHelpers.psm1') -Force
        Register-CommandStub -Name Get-CimInstance -Parameter ClassName, Namespace, Filter, ComputerName
        Register-CommandStub -Name Invoke-CimMethod -Parameter InputObject, MethodName
    }

    AfterAll {
        Remove-CommandStub -Name Get-CimInstance, Invoke-CimMethod
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

    It 'Get-BitLockerEncryptableVolume passes -ComputerName only for a remote computer' {
        Mock Get-CimInstance -ModuleName SecurityPosture { 'volume' }
        InModuleScope SecurityPosture { Get-BitLockerEncryptableVolume } | Should -Be 'volume'
        InModuleScope SecurityPosture { Get-BitLockerEncryptableVolume -ComputerName 'PC02' } | Should -Be 'volume'
        Should -Invoke Get-CimInstance -ModuleName SecurityPosture -Times 1 -Exactly -ParameterFilter {
            $ClassName -eq 'Win32_EncryptableVolume' -and $Filter -eq 'DriveLetter IS NOT NULL' -and -not $PesterBoundParameters.ContainsKey('ComputerName')
        }
        Should -Invoke Get-CimInstance -ModuleName SecurityPosture -Times 1 -Exactly -ParameterFilter { $ComputerName -eq 'PC02' }
    }

    It 'Get-BitLockerEncryptionPercentage returns EncryptionPercentage from GetConversionStatus' {
        Mock Invoke-CimMethod -ModuleName SecurityPosture { [pscustomobject]@{ EncryptionPercentage = [uint32]37 } }
        InModuleScope SecurityPosture { Get-BitLockerEncryptionPercentage -Volume 'volume' } | Should -Be 37
        Should -Invoke Invoke-CimMethod -ModuleName SecurityPosture -Times 1 -Exactly -ParameterFilter { $MethodName -eq 'GetConversionStatus' }
    }
}

Describe 'Get-BitLockerVolumeStatus' {
    BeforeAll {
        $script:idC = [guid]'11111111-2222-3333-4444-555555555555'
        $script:idD = [guid]'66666666-7777-8888-9999-aaaaaaaaaaaa'
    }

    BeforeEach {
        # CIM returns UInt32 status codes; the old script's string-keyed lookup missed them.
        Mock Get-BitLockerEncryptableVolume -ModuleName SecurityPosture {
            [pscustomobject]@{ DriveLetter = 'D:'; ProtectionStatus = [uint32]0; ConversionStatus = [uint32]2; PersistentVolumeID = "{$script:idD}" }
            [pscustomobject]@{ DriveLetter = 'C:'; ProtectionStatus = [uint32]1; ConversionStatus = [uint32]1; PersistentVolumeID = "{$($script:idC.ToString().ToUpper())}" }
            [pscustomobject]@{ DriveLetter = 'E:'; ProtectionStatus = [uint32]2; ConversionStatus = [uint32]0; PersistentVolumeID = '' }
        }
        Mock Get-BitLockerEncryptionPercentage -ModuleName SecurityPosture { [uint32]42 }
        Mock Get-BitLockerAdRecoveryInfo -ModuleName SecurityPosture {
            [pscustomobject]@{ VolumeId = $script:idC; BackupDate = [datetime]'2025-01-01' }
            [pscustomobject]@{ VolumeId = $script:idC; BackupDate = [datetime]'2026-03-04' }
            [pscustomobject]@{ VolumeId = [guid]::NewGuid(); BackupDate = [datetime]'2026-05-05' }
        }
    }

    It 'returns one row per volume, sorted by drive letter, with named status codes' {
        $rows = @(Get-BitLockerVolumeStatus)
        @($rows.DriveLetter) | Should -Be @('C:', 'D:', 'E:')
        @($rows.ProtectionStatus) | Should -Be @('Protected', 'Unprotected', 'Unknown')
        @($rows.ConversionStatus) | Should -Be @('Fully Encrypted', 'Encryption in Progress', 'Fully Decrypted')
        $rows[0].ComputerName | Should -Be ([Environment]::MachineName)
    }

    It 'reads the encryption percentage only for a converting or paused volume' {
        $rows = @(Get-BitLockerVolumeStatus)
        $rows[1].EncryptionPercentage | Should -Be 42
        $rows[0].EncryptionPercentage | Should -BeNullOrEmpty
        Should -Invoke Get-BitLockerEncryptionPercentage -ModuleName SecurityPosture -Times 1 -Exactly -ParameterFilter { $Volume.DriveLetter -eq 'D:' }
    }

    It 'joins each volume to its newest AD recovery entry by volume GUID, ignoring case' {
        $rows = @(Get-BitLockerVolumeStatus)
        $rows[0].VolumeId | Should -Be $script:idC
        $rows[0].BackupDate | Should -Be ([datetime]'2026-03-04')
        $rows[1].BackupDate | Should -BeNullOrEmpty
        $rows[2].VolumeId | Should -BeNullOrEmpty
    }

    It 'reports RecoveryKeyEscrowed True when AD holds an entry for the volume, False when it holds none' {
        $rows = @(Get-BitLockerVolumeStatus)
        $rows[0].RecoveryKeyEscrowed | Should -BeTrue
        $rows[1].RecoveryKeyEscrowed | Should -BeOfType [bool]
        $rows[1].RecoveryKeyEscrowed | Should -BeFalse
        # E: has no VolumeId to join on, so escrow is unknown rather than False.
        $rows[2].RecoveryKeyEscrowed | Should -BeNullOrEmpty
        @($rows[0].PSObject.Properties.Name) | Should -Be @('ComputerName', 'DriveLetter', 'ProtectionStatus', 'ConversionStatus', 'EncryptionPercentage', 'VolumeId', 'BackupDate', 'RecoveryKeyEscrowed')
    }

    It 'queries this computer directly for <Name>' -ForEach @(@{ Name = '.' }, @{ Name = 'localhost' }, @{ Name = [Environment]::MachineName.ToLower() }) {
        $rows = @(Get-BitLockerVolumeStatus -ComputerName $Name)
        $rows[0].ComputerName | Should -Be ([Environment]::MachineName)
        Should -Invoke Get-BitLockerEncryptableVolume -ModuleName SecurityPosture -Times 1 -Exactly -ParameterFilter { -not $ComputerName }
        Should -Invoke Get-BitLockerAdRecoveryInfo -ModuleName SecurityPosture -Times 1 -Exactly -ParameterFilter { $ComputerName -eq [Environment]::MachineName }
    }

    It 'queries a remote computer by name' {
        $null = Get-BitLockerVolumeStatus -ComputerName 'REMOTE-PC'
        Should -Invoke Get-BitLockerEncryptableVolume -ModuleName SecurityPosture -Times 1 -Exactly -ParameterFilter { $ComputerName -eq 'REMOTE-PC' }
    }

    It 'still returns the volumes when the AD lookup fails' {
        Mock Get-BitLockerAdRecoveryInfo -ModuleName SecurityPosture { throw 'The specified domain either does not exist' }
        $rows = @(Get-BitLockerVolumeStatus -ErrorVariable errs -ErrorAction SilentlyContinue)
        $rows | Should -HaveCount 3
        $rows[0].BackupDate | Should -BeNullOrEmpty
        # Unknown, not False: a failed lookup says nothing about escrow.
        @($rows | Where-Object { $null -ne $_.RecoveryKeyEscrowed }) | Should -BeNullOrEmpty
        "$($errs[-1])" | Should -Match 'Active Directory.*domain either does not exist'
    }

    It 'writes a non-terminating error and returns nothing when the volumes cannot be read' {
        Mock Get-BitLockerEncryptableVolume -ModuleName SecurityPosture { throw 'Access denied' }
        $rows = Get-BitLockerVolumeStatus -ErrorVariable errs -ErrorAction SilentlyContinue
        $rows | Should -BeNullOrEmpty
        "$($errs[-1])" | Should -Match 'BitLocker volumes.*Access denied'
        Should -Invoke Get-BitLockerAdRecoveryInfo -ModuleName SecurityPosture -Times 0 -Exactly
    }
}

Describe 'Get-BitLockerAdRecoveryInfo' {
    BeforeAll {
        # The only attributes the lookup may load. AD returns every readable attribute when
        # PropertiesToLoad is empty, which includes the recovery password and LAPS passwords.
        $script:allowedAttributes = @('distinguishedname', 'name', 'msfve-volumeguid')
    }

    BeforeEach {
        $volumeId = [guid]'0a0b0c0d-1111-2222-3333-444455556666'
        # A fake DirectorySearcher. Like AD, it returns only the attributes in PropertiesToLoad
        # (plus adspath), or every attribute when the list is empty; it records the filter and
        # a snapshot of PropertiesToLoad for every search, and which objects were disposed.
        $script:fake = [pscustomobject]@{
            Filter = $null; SearchRoot = $null; PageSize = 0
            PropertiesToLoad = [System.Collections.Generic.List[string]]::new()
            Calls = [System.Collections.Generic.List[object]]::new()
            Disposed = [System.Collections.Generic.List[string]]::new()
            FindCount = 0
            Computer = @{
                distinguishedname = @('CN=PC01,OU=Computers'); 'ms-mcs-admpwd' = @('fake-laps-password')
                'mstpm-ownerinformation' = @('fake-tpm-owner')
            }
            Entries = @(
                @{ distinguishedname = @('CN=a,CN=PC01'); name = @('2026-01-02T03:04:05-08:00{AAAA}'); 'msfve-volumeguid' = @(, $volumeId.ToByteArray()); 'msfve-recoverypassword' = @('111111-222222') }
                @{ distinguishedname = @('CN=b,CN=PC01'); name = @('2026-02-02T03:04:05-08:00{BBBB}'); 'msfve-volumeguid' = @(, $volumeId.ToByteArray()); 'msfve-recoverypassword' = @('333333-444444') }
            )
        }
        $script:fake | Add-Member -MemberType ScriptMethod -Name Project -Value {
            param($Source)
            $requested = @($this.PropertiesToLoad)
            $out = @{ adspath = @('LDAP://fake') }
            foreach ($key in $Source.Keys) {
                if ($requested.Count -eq 0 -or $requested -contains $key) { $out[$key] = $Source[$key] }
            }
            $out
        }
        $script:fake | Add-Member -MemberType ScriptMethod -Name Record -Value {
            param($Method)
            $this.Calls.Add([pscustomobject]@{ Method = $Method; Filter = $this.Filter; Properties = [string[]]@($this.PropertiesToLoad) })
        }
        $script:fake | Add-Member -MemberType ScriptMethod -Name FindOne -Value {
            $this.Record('FindOne')
            if ($this.Computer) {
                $entry = [pscustomobject]@{ Path = 'LDAP://CN=PC01' } |
                    Add-Member -MemberType ScriptMethod -Name Dispose -Value { $script:fake.Disposed.Add('entry') } -PassThru
                [pscustomobject]@{ Properties = $this.Project($this.Computer); Entry = $entry } |
                    Add-Member -MemberType ScriptMethod -Name GetDirectoryEntry -Value { $this.Entry } -PassThru
            }
        }
        $script:fake | Add-Member -MemberType ScriptMethod -Name FindAll -Value {
            $this.Record('FindAll')
            $list = [System.Collections.ArrayList]::new()
            foreach ($e in $this.Entries) { $null = $list.Add([pscustomobject]@{ Properties = $this.Project($e) }) }
            Add-Member -InputObject $list -MemberType ScriptMethod -Name Dispose -Value { $script:fake.Disposed.Add('results') } -PassThru
        }
        $script:fake | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.Disposed.Add('searcher') }
        Mock New-Object -ModuleName SecurityPosture { $script:fake } -ParameterFilter { $TypeName -eq 'System.DirectoryServices.DirectorySearcher' }
    }

    It 'returns one object per recovery entry, with VolumeId and BackupDate' {
        $result = @(InModuleScope SecurityPosture { Get-BitLockerAdRecoveryInfo -ComputerName 'PC01.corp.example' })
        $result | Should -HaveCount 2
        @($result[0].PSObject.Properties.Name) | Should -Be @('VolumeId', 'BackupDate')
        $result[0].VolumeId | Should -Be ([guid]'0a0b0c0d-1111-2222-3333-444455556666')
        $result[1].BackupDate | Should -Be ([DateTimeOffset]'2026-02-02T03:04:05-08:00').LocalDateTime
    }

    It 'names a non-empty list of non-confidential attributes before every search' {
        $null = InModuleScope SecurityPosture { Get-BitLockerAdRecoveryInfo -ComputerName 'PC01' }
        @($script:fake.Calls.Method) | Should -Be @('FindOne', 'FindAll')
        foreach ($call in $script:fake.Calls) {
            $call.Properties | Should -Not -BeNullOrEmpty -Because "$($call.Method) $($call.Filter) must not load every attribute"
            foreach ($attribute in $call.Properties) {
                $attribute | Should -BeIn $script:allowedAttributes
                $attribute | Should -Not -Match 'password|keypackage|admpwd|laps|tpm'
            }
        }
        $script:fake.Calls[0].Properties | Should -Be @('distinguishedname')
    }

    It 'matches the computer on sAMAccountName and searches only below it, without paging' {
        $null = InModuleScope SecurityPosture { Get-BitLockerAdRecoveryInfo -ComputerName 'PC01.corp.example' }
        $script:fake.Calls[0].Filter | Should -Be '(&(objectCategory=computer)(sAMAccountName=PC01$))'
        $script:fake.Calls[1].Filter | Should -Be '(objectClass=msFVE-RecoveryInformation)'
        $script:fake.SearchRoot.Path | Should -Be 'LDAP://CN=PC01'
        $script:fake.PageSize | Should -Be 0
    }

    It 'cuts a long name to the 15-character NetBIOS name that sAMAccountName holds' {
        $null = InModuleScope SecurityPosture { Get-BitLockerAdRecoveryInfo -ComputerName 'ABCDEFGHIJKLMNOPQ.corp.example' }
        $script:fake.Calls[0].Filter | Should -Be '(&(objectCategory=computer)(sAMAccountName=ABCDEFGHIJKLMNO$))'
    }

    It 'disposes the directory entry, the results and the searcher' {
        $null = InModuleScope SecurityPosture { Get-BitLockerAdRecoveryInfo -ComputerName 'PC01' }
        @($script:fake.Disposed | Sort-Object) | Should -Be @('entry', 'results', 'searcher')
    }

    It 'escapes LDAP filter characters, including NUL ([char]0), and throws when the computer is not found' {
        $script:fake.Computer = $null
        $name = 'a*b(c)\d' + [char]0 + 'e'
        { InModuleScope SecurityPosture -Parameters @{ Name = $name } { param($Name) Get-BitLockerAdRecoveryInfo -ComputerName $Name } } | Should -Throw '*not found*'
        $script:fake.Calls[0].Filter | Should -Be '(&(objectCategory=computer)(sAMAccountName=a\2ab\28c\29\5cd\00e$))'
        @($script:fake.Disposed) | Should -Be @('searcher')
    }

    It 'skips the AD lookup with a clear error for the IP address <Address>' -ForEach @(@{ Address = '10.1.2.3' }, @{ Address = 'fe80::1' }) {
        { InModuleScope SecurityPosture -Parameters @{ Address = $Address } { param($Address) Get-BitLockerAdRecoveryInfo -ComputerName $Address } } | Should -Throw '*IP address*'
        Should -Invoke New-Object -ModuleName SecurityPosture -Times 0 -Exactly -ParameterFilter { $TypeName -eq 'System.DirectoryServices.DirectorySearcher' }
    }

    It 'still returns the volumes, with an IP address error, when Get-BitLockerVolumeStatus gets an IP address' {
        Mock Get-BitLockerEncryptableVolume -ModuleName SecurityPosture {
            [pscustomobject]@{ DriveLetter = 'C:'; ProtectionStatus = [uint32]1; ConversionStatus = [uint32]1; PersistentVolumeID = '' }
        }
        $rows = @(Get-BitLockerVolumeStatus -ComputerName '10.1.2.3' -ErrorVariable errs -ErrorAction SilentlyContinue)
        $rows | Should -HaveCount 1
        "$($errs[-1])" | Should -Match 'IP address'
        $script:fake.Calls | Should -BeNullOrEmpty
    }

    It 'names msFVE-RecoveryPassword in no code token under Modules/ or Scripts/' {
        # The repository never reads BitLocker recovery passwords (#110, #122); a recovery
        # information entry is itself the proof of escrow.
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $files = Get-ChildItem -Path (Join-Path $repoRoot 'Modules'), (Join-Path $repoRoot 'Scripts') -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1'
        $files | Should -Not -BeNullOrEmpty
        $offenders = foreach ($file in $files) {
            $tokens = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$null)
            foreach ($token in @($tokens | Where-Object { $_.Kind -ne 'Comment' -and $_.Text -match 'msfve-recoverypassword' })) {
                '{0}:{1}' -f $file.Name, $token.Extent.StartLineNumber
            }
        }
        $offenders | Should -BeNullOrEmpty
    }
}

Describe 'ConvertFrom-BitLockerRecoveryEntry' {
    It 'parses the backup time from the name and the volume GUID from its bytes' {
        $id = [guid]'0a0b0c0d-1111-2222-3333-444455556666'
        $entry = InModuleScope SecurityPosture -Parameters @{ Bytes = $id.ToByteArray() } {
            param($Bytes)
            ConvertFrom-BitLockerRecoveryEntry -Name '2026-01-02T03:04:05-08:00{ABCD}' -VolumeGuid $Bytes
        }
        $entry.VolumeId | Should -Be $id
        $entry.BackupDate | Should -Be ([DateTimeOffset]'2026-01-02T03:04:05-08:00').LocalDateTime
    }

    It 'leaves BackupDate and VolumeId empty when they cannot be read' {
        $entry = InModuleScope SecurityPosture { ConvertFrom-BitLockerRecoveryEntry -Name 'not-a-date{ABCD}' -VolumeGuid $null }
        $entry.BackupDate | Should -BeNullOrEmpty
        $entry.VolumeId | Should -BeNullOrEmpty
    }
}
