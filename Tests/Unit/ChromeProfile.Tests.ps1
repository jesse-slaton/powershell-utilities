#Requires -Version 5.1
# Behavior tests for Modules/ChromeProfile. The module is imported (it only defines functions).
# Every file effect stays in $TestDrive: the default-location helpers are mocked, and the real
# Compress-Archive / Expand-Archive run on files there, so these run on any OS.

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'Modules/ChromeProfile/ChromeProfile.psd1') -Force

    # Non-ASCII built from code points so this file stays ASCII: 'naive' with i-diaeresis, u-umlaut.
    $script:nonAsciiName = 'na' + [char]0x00EF + 've-' + [char]0x00FC + '.txt'
    $script:binaryBytes = [byte[]](0..255)

    # A profile with what Compress-Archive / Expand-Archive treat differently between 5.1 and 7:
    # a name with spaces and non-ASCII characters, an empty folder, multi-level nesting, binary data.
    function Initialize-FakeChromeProfile {
        param([string]$Path, [string]$Bookmarks = '{"roots":{}}')
        $null = New-Item -ItemType Directory -Path (Join-Path $Path 'Extensions') -Force
        Set-Content -LiteralPath (Join-Path $Path 'Bookmarks') -Value $Bookmarks
        Set-Content -LiteralPath (Join-Path $Path 'Extensions/marker.txt') -Value 'nested'
        $subDir = New-Item -ItemType Directory -Path (Join-Path $Path 'Sub Dir') -Force
        [System.IO.File]::WriteAllText((Join-Path $subDir.FullName $script:nonAsciiName), 'unicode')
        # Nested: Compress-Archive drops an empty folder at the top of a wildcard source (see the help).
        $null = New-Item -ItemType Directory -Path (Join-Path $Path 'Sub Dir/Empty Folder') -Force
        $deep = New-Item -ItemType Directory -Path (Join-Path $Path 'Level1/Level2/Level3') -Force
        Set-Content -LiteralPath (Join-Path $deep.FullName 'deep.txt') -Value 'deep'
        [System.IO.File]::WriteAllBytes((Join-Path $Path 'Cache.bin'), $script:binaryBytes)
    }

    function Assert-FakeChromeProfile {
        param([string]$Path)
        Get-Content -LiteralPath (Join-Path $Path 'Extensions/marker.txt') | Should -Be 'nested'
        [System.IO.File]::ReadAllText((Join-Path $Path ('Sub Dir/' + $script:nonAsciiName))) | Should -Be 'unicode'
        Test-Path -LiteralPath (Join-Path $Path 'Sub Dir/Empty Folder') -PathType Container | Should -BeTrue -Because 'an empty folder must survive the round trip'
        Get-Content -LiteralPath (Join-Path $Path 'Level1/Level2/Level3/deep.txt') | Should -Be 'deep'
        $bytes = [System.IO.File]::ReadAllBytes((Join-Path $Path 'Cache.bin'))
        [System.Convert]::ToBase64String($bytes) | Should -Be ([System.Convert]::ToBase64String($script:binaryBytes))
    }

    # A zip in the layout the old ChromeProfileBackup.ps1 wrote: every entry under ChromeProfileBackup.
    function New-LegacyBackupZip {
        param([string]$Path, [string]$Separator)
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($name in 'Bookmarks', ('Extensions' + $Separator + 'marker.txt')) {
                $writer = New-Object System.IO.StreamWriter(($archive.CreateEntry('ChromeProfileBackup' + $Separator + $name)).Open())
                try { $writer.Write('old') } finally { $writer.Dispose() }
            }
        }
        finally {
            $archive.Dispose()
        }
    }
}

AfterAll {
    Remove-Module -Name ChromeProfile -Force -ErrorAction SilentlyContinue
}

Describe 'Backup-ChromeProfile' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        $chromeProfile = Join-Path $root 'User Data/Default'
        $backup = Join-Path $root 'backup'
        Initialize-FakeChromeProfile -Path $chromeProfile
    }

    It 'zips the profile contents at the zip root, creating the destination folder' {
        $result = Backup-ChromeProfile -Destination $backup -ProfilePath $chromeProfile

        $result | Should -BeOfType System.IO.FileInfo
        $result.FullName | Should -Be (Join-Path $backup 'ChromeProfileBackup.zip')
        $out = Join-Path $root 'expanded'
        Expand-Archive -LiteralPath $result.FullName -DestinationPath $out
        Get-Content -LiteralPath (Join-Path $out 'Bookmarks') | Should -Be '{"roots":{}}'
        Get-Content -LiteralPath (Join-Path $out 'Extensions/marker.txt') | Should -Be 'nested'
        Test-Path -LiteralPath (Join-Path $out 'Default') | Should -BeFalse -Because 'the zip holds the contents, not a folder named after the profile'
    }

    It 'replaces an existing backup zip' {
        $null = Backup-ChromeProfile -Destination $backup -ProfilePath $chromeProfile
        Set-Content -LiteralPath (Join-Path $chromeProfile 'Bookmarks') -Value 'second'

        $result = Backup-ChromeProfile -Destination $backup -ProfilePath $chromeProfile

        $out = Join-Path $root 'expanded'
        Expand-Archive -LiteralPath $result.FullName -DestinationPath $out
        Get-Content -LiteralPath (Join-Path $out 'Bookmarks') | Should -Be 'second'
    }

    It 'uses the default backup folder and profile when no parameters are given' {
        Mock Get-ChromeDefaultBackupFolder -ModuleName ChromeProfile { $backup }
        Mock Get-ChromeDefaultProfilePath -ModuleName ChromeProfile { $chromeProfile }

        $result = Backup-ChromeProfile

        $result.FullName | Should -Be (Join-Path $backup 'ChromeProfileBackup.zip')
        Should -Invoke Get-ChromeDefaultBackupFolder -ModuleName ChromeProfile -Times 1 -Exactly
        Should -Invoke Get-ChromeDefaultProfilePath -ModuleName ChromeProfile -Times 1 -Exactly
    }

    It 'writes an error and creates nothing when the profile folder is missing' {
        $missing = Join-Path $root 'User Data/Profile 9'

        $result = Backup-ChromeProfile -Destination $backup -ProfilePath $missing -ErrorVariable err -ErrorAction SilentlyContinue

        $result | Should -BeNullOrEmpty
        "$err" | Should -BeLike '*Chrome profile folder not found*'
        Test-Path -LiteralPath $backup | Should -BeFalse
    }

    It 'keeps the previous backup zip and removes the partial one when a backup fails' {
        $first = Backup-ChromeProfile -Destination $backup -ProfilePath $chromeProfile
        $before = (Get-FileHash -LiteralPath $first.FullName).Hash
        Mock Compress-Archive -ModuleName ChromeProfile {
            Set-Content -LiteralPath $DestinationPath -Value 'partial'
            throw 'file locked'
        }

        $result = Backup-ChromeProfile -Destination $backup -ProfilePath $chromeProfile -ErrorVariable err -ErrorAction SilentlyContinue

        $result | Should -BeNullOrEmpty
        "$err" | Should -BeLike '*file locked*'
        (Get-FileHash -LiteralPath $first.FullName).Hash | Should -Be $before -Because 'a failed backup must not destroy the last good one'
        @(Get-ChildItem -LiteralPath $backup).Name | Should -Be @('ChromeProfileBackup.zip')
    }

    It 'writes an error and outputs nothing when the zip cannot be written' {
        Mock Compress-Archive -ModuleName ChromeProfile { throw 'disk full' }

        $result = Backup-ChromeProfile -Destination $backup -ProfilePath $chromeProfile -ErrorVariable err -ErrorAction SilentlyContinue

        $result | Should -BeNullOrEmpty
        "$err" | Should -BeLike '*Error backing up Chrome profile*disk full*'
    }
}

Describe 'Restore-ChromeProfile' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        $chromeProfile = Join-Path $root 'User Data/Default'
        $backup = Join-Path $root 'backup'
        $zip = Join-Path $backup 'ChromeProfileBackup.zip'
    }

    It 'restores a missing profile from a Backup-ChromeProfile zip and deletes the zip' {
        # Brackets in the path: Compress-Archive -Path is wildcard-expanded, so it must be escaped.
        $chromeProfile = Join-Path $root 'User Data/Profile [1]'
        Initialize-FakeChromeProfile -Path $chromeProfile -Bookmarks 'saved'
        $null = Backup-ChromeProfile -Destination $backup -ProfilePath $chromeProfile -ErrorAction Stop
        Remove-Item -LiteralPath $chromeProfile -Recurse -Force

        $result = Restore-ChromeProfile -Path $backup -ProfilePath $chromeProfile

        $result | Should -BeOfType System.IO.DirectoryInfo
        $result.FullName | Should -Be (Get-Item -LiteralPath $chromeProfile).FullName
        Get-Content -LiteralPath (Join-Path $chromeProfile 'Bookmarks') | Should -Be 'saved'
        Assert-FakeChromeProfile -Path $chromeProfile
        Test-Path -LiteralPath $zip | Should -BeFalse
    }

    It 'refuses a zip in the old backup script layout (<Separator> separators), keeping it and creating nothing' -TestCases @(
        @{ Separator = '/' }
        @{ Separator = '\' }
    ) {
        param($Separator)
        New-LegacyBackupZip -Path $zip -Separator $Separator
        $before = (Get-FileHash -LiteralPath $zip).Hash

        $result = Restore-ChromeProfile -Path $backup -ProfilePath $chromeProfile -ErrorVariable err -ErrorAction SilentlyContinue

        $result | Should -BeNullOrEmpty
        "$err" | Should -BeLike '*old ChromeProfileBackup.ps1*copy the contents of its ChromeProfileBackup folder*'
        (Get-FileHash -LiteralPath $zip).Hash | Should -Be $before
        Test-Path -LiteralPath $chromeProfile | Should -BeFalse
    }

    It 'warns and leaves an existing profile and the zip alone' {
        Initialize-FakeChromeProfile -Path $chromeProfile -Bookmarks 'saved'
        $null = Backup-ChromeProfile -Destination $backup -ProfilePath $chromeProfile
        Set-Content -LiteralPath (Join-Path $chromeProfile 'Bookmarks') -Value 'current'

        $result = Restore-ChromeProfile -Path $backup -ProfilePath $chromeProfile -WarningVariable warn -WarningAction SilentlyContinue

        $result | Should -BeNullOrEmpty
        "$warn" | Should -BeLike '*already exists*'
        Get-Content -LiteralPath (Join-Path $chromeProfile 'Bookmarks') | Should -Be 'current'
        Test-Path -LiteralPath $zip | Should -BeTrue
    }

    It 'warns and creates nothing when there is no backup zip' {
        $result = Restore-ChromeProfile -Path $backup -ProfilePath $chromeProfile -WarningVariable warn -WarningAction SilentlyContinue

        $result | Should -BeNullOrEmpty
        "$warn" | Should -BeLike '*No backup file found*'
        Test-Path -LiteralPath $chromeProfile | Should -BeFalse
    }

    It 'keeps the zip, removes the partial profile and writes an error when extraction fails' {
        $null = New-Item -ItemType Directory -Path $backup -Force
        Set-Content -LiteralPath $zip -Value 'not a zip'

        $result = Restore-ChromeProfile -Path $backup -ProfilePath $chromeProfile -ErrorVariable err -ErrorAction SilentlyContinue

        $result | Should -BeNullOrEmpty
        "$err" | Should -BeLike '*Error restoring Chrome profile*'
        Test-Path -LiteralPath $zip | Should -BeTrue
        Test-Path -LiteralPath $chromeProfile | Should -BeFalse -Because 'a partial extraction must not block the next restore'
    }

    It 'uses the default backup folder and profile when no parameters are given' {
        Initialize-FakeChromeProfile -Path $chromeProfile
        $null = Backup-ChromeProfile -Destination $backup -ProfilePath $chromeProfile
        Remove-Item -LiteralPath $chromeProfile -Recurse -Force
        Mock Get-ChromeDefaultBackupFolder -ModuleName ChromeProfile { $backup }
        Mock Get-ChromeDefaultProfilePath -ModuleName ChromeProfile { $chromeProfile }

        $result = Restore-ChromeProfile

        $result | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath (Join-Path $chromeProfile 'Bookmarks') | Should -BeTrue
        Should -Invoke Get-ChromeDefaultBackupFolder -ModuleName ChromeProfile -Times 1 -Exactly
    }
}

Describe 'ChromeProfile default locations' {
    It 'builds the Default profile and backup folder paths from the environment' {
        InModuleScope ChromeProfile {
            $saved = $env:LOCALAPPDATA, $env:USERPROFILE
            try {
                $env:LOCALAPPDATA = Join-Path $TestDrive 'Local'
                $env:USERPROFILE = Join-Path $TestDrive 'Home'
                Get-ChromeDefaultProfilePath | Should -Be ([System.IO.Path]::Combine($env:LOCALAPPDATA, 'Google', 'Chrome', 'User Data', 'Default'))
                Get-ChromeDefaultBackupFolder | Should -Be (Join-Path $env:USERPROFILE 'ChromeBackup')
            }
            finally {
                $env:LOCALAPPDATA, $env:USERPROFILE = $saved
            }
        }
    }
}
