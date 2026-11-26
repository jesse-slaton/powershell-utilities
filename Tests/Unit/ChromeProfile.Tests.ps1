#Requires -Version 5.1
# Behavior tests for Modules/ChromeProfile. The module is imported (it only defines functions).
# Every file effect stays in $TestDrive: the default-location helpers are mocked, and the
# real zip code (System.IO.Compression) runs on files there, so these run on any OS.

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $repoRoot 'Modules/ChromeProfile/ChromeProfile.psd1') -Force

    # Non-ASCII built from code points so this file stays ASCII: 'naive' with i-diaeresis, u-umlaut.
    $script:nonAsciiName = 'na' + [char]0x00EF + 've-' + [char]0x00FC + '.txt'
    $script:binaryBytes = [byte[]](0..255)

    # A profile with what zip handling can get wrong: a name with spaces and non-ASCII characters,
    # an empty folder, multi-level nesting, binary data.
    function Initialize-FakeChromeProfile {
        param([string]$Path, [string]$Bookmarks = '{"roots":{}}')
        $null = New-Item -ItemType Directory -Path (Join-Path $Path 'Extensions') -Force
        Set-Content -LiteralPath (Join-Path $Path 'Bookmarks') -Value $Bookmarks
        Set-Content -LiteralPath (Join-Path $Path 'Extensions/marker.txt') -Value 'nested'
        $subDir = New-Item -ItemType Directory -Path (Join-Path $Path 'Sub Dir') -Force
        [System.IO.File]::WriteAllText((Join-Path $subDir.FullName $script:nonAsciiName), 'unicode')
        # Nested empty folder.
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

    # Hidden content: a dot-name is the hidden analogue on macOS/Linux; on Windows the Hidden
    # attribute is set too (Compress-Archive skipped those).
    function Add-HiddenProfileContent {
        param([string]$Path)
        $hiddenFile = Join-Path $Path '.hidden-file'
        Set-Content -LiteralPath $hiddenFile -Value 'hidden'
        $hiddenDir = New-Item -ItemType Directory -Path (Join-Path $Path '.hidden-dir/inner') -Force
        Set-Content -LiteralPath (Join-Path $hiddenDir.FullName 'in-hidden.txt') -Value 'in hidden'
        $null = New-Item -ItemType Directory -Path (Join-Path $Path 'Level1/Empty Deep/Empty Deeper') -Force
        $null = New-Item -ItemType Directory -Path (Join-Path $Path 'Empty Top') -Force
        if ($env:OS -eq 'Windows_NT') {
            $visibleHidden = Join-Path $Path 'Level1/attr-hidden.txt'
            Set-Content -LiteralPath $visibleHidden -Value 'attr'
            (Get-Item -LiteralPath $visibleHidden -Force).Attributes = 'Hidden'
            (Get-Item -LiteralPath (Join-Path $Path '.hidden-file') -Force).Attributes = 'Hidden'
            (Get-Item -LiteralPath (Join-Path $Path '.hidden-dir') -Force).Attributes = 'Hidden, Directory'
        }
    }

    function Assert-HiddenProfileContent {
        param([string]$Path)
        Get-Content -LiteralPath (Join-Path $Path '.hidden-file') | Should -Be 'hidden'
        Get-Content -LiteralPath (Join-Path $Path '.hidden-dir/inner/in-hidden.txt') | Should -Be 'in hidden'
        Test-Path -LiteralPath (Join-Path $Path 'Level1/Empty Deep/Empty Deeper') -PathType Container | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $Path 'Empty Top') -PathType Container | Should -BeTrue -Because 'an empty folder directly in the profile must survive'
        if ($env:OS -eq 'Windows_NT') {
            Get-Content -LiteralPath (Join-Path $Path 'Level1/attr-hidden.txt') | Should -Be 'attr'
        }
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

    It 'writes into a bracketed destination literally, never into a folder the brackets match as a wildcard' {
        # 'Backup [1]' read as a wildcard pattern matches 'Backup 1'.
        $decoy = Join-Path $root 'Backup 1'
        $null = New-Item -ItemType Directory -Path $decoy -Force
        $bracketed = Join-Path $root 'Backup [1]'

        $result = Backup-ChromeProfile -Destination $bracketed -ProfilePath $chromeProfile -ErrorAction Stop

        $literalZip = Join-Path $bracketed 'ChromeProfileBackup.zip'
        $result.FullName | Should -Be (Get-Item -LiteralPath $literalZip).FullName
        Test-Path -LiteralPath (Join-Path $bracketed 'ChromeProfileBackup.partial.zip') | Should -BeFalse
        @(Get-ChildItem -LiteralPath $decoy -Force) | Should -BeNullOrEmpty -Because 'the look-alike folder must stay untouched'
    }

    It 'includes hidden files and folders and empty folders at any depth in the zip' {
        Add-HiddenProfileContent -Path $chromeProfile

        $result = Backup-ChromeProfile -Destination $backup -ProfilePath $chromeProfile -ErrorAction Stop

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead($result.FullName)
        try { $names = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') }) } finally { $archive.Dispose() }
        $names | Should -Contain '.hidden-file'
        $names | Should -Contain '.hidden-dir/inner/in-hidden.txt'
        $names | Should -Contain 'Empty Top/'
        $names | Should -Contain 'Level1/Empty Deep/Empty Deeper/'
        if ($env:OS -eq 'Windows_NT') { $names | Should -Contain 'Level1/attr-hidden.txt' }
    }

    It 'backs up a bracketed profile into a bracketed destination, never touching look-alike folders' {
        $bracketedProfile = Join-Path $root 'User Data/Profile [1]'
        Initialize-FakeChromeProfile -Path $bracketedProfile -Bookmarks 'bracketed'
        $decoyProfile = Join-Path $root 'User Data/Profile 1'
        Initialize-FakeChromeProfile -Path $decoyProfile -Bookmarks 'decoy'
        $decoyBackup = Join-Path $root 'Backup 1'
        $null = New-Item -ItemType Directory -Path $decoyBackup -Force
        $bracketedBackup = Join-Path $root 'Backup [1]'

        $result = Backup-ChromeProfile -Destination $bracketedBackup -ProfilePath $bracketedProfile -ErrorAction Stop

        $out = Join-Path $root 'expanded'
        Expand-Archive -LiteralPath $result.FullName -DestinationPath $out
        Get-Content -LiteralPath (Join-Path $out 'Bookmarks') | Should -Be 'bracketed'
        @(Get-ChildItem -LiteralPath $decoyBackup -Force) | Should -BeNullOrEmpty
    }

    It 'resolves relative -Destination and -ProfilePath against the PowerShell location, not the process directory' {
        Push-Location $root
        try {
            $result = Backup-ChromeProfile -Destination 'rel-backup' -ProfilePath 'User Data/Default' -ErrorAction Stop
        }
        finally { Pop-Location }

        $result.FullName | Should -Be (Join-Path (Get-Item -LiteralPath $root).FullName 'rel-backup/ChromeProfileBackup.zip')
    }

    It 'refuses a folder whose only top-level item is a ChromeProfileBackup folder, which Restore-ChromeProfile would read as the old layout' {
        $odd = Join-Path $root 'User Data/Odd'
        $null = New-Item -ItemType Directory -Path (Join-Path $odd 'ChromeProfileBackup') -Force
        Set-Content -LiteralPath (Join-Path $odd 'ChromeProfileBackup/note.txt') -Value 'x'

        $result = Backup-ChromeProfile -Destination $backup -ProfilePath $odd -ErrorVariable err -ErrorAction SilentlyContinue

        $result | Should -BeNullOrEmpty
        "$err" | Should -BeLike '*ChromeProfileBackup*could not be restored*'
        Test-Path -LiteralPath (Join-Path $backup 'ChromeProfileBackup.zip') | Should -BeFalse
    }

    It 'backs up a profile that has a ChromeProfileBackup folder next to other items' {
        $null = New-Item -ItemType Directory -Path (Join-Path $chromeProfile 'ChromeProfileBackup') -Force
        Set-Content -LiteralPath (Join-Path $chromeProfile 'ChromeProfileBackup/note.txt') -Value 'x'

        $result = Backup-ChromeProfile -Destination $backup -ProfilePath $chromeProfile -ErrorAction Stop

        $result.Name | Should -Be 'ChromeProfileBackup.zip'
    }

    It 'leaves partial zips of other runs alone and leaves none of its own behind' {
        # Another backup to the same folder may be writing its own partial zip right now.
        $null = New-Item -ItemType Directory -Path $backup -Force
        $others = @('ChromeProfileBackup.partial.zip', 'ChromeProfileBackup.partial-0123456789abcdef.zip')
        foreach ($name in $others) { Set-Content -LiteralPath (Join-Path $backup $name) -Value 'other run' }

        $result = Backup-ChromeProfile -Destination $backup -ProfilePath $chromeProfile -ErrorAction Stop

        $result.Name | Should -Be 'ChromeProfileBackup.zip'
        foreach ($name in $others) {
            Get-Content -LiteralPath (Join-Path $backup $name) | Should -Be 'other run' -Because 'a partial zip this call did not write is not its to remove'
        }
        @(Get-ChildItem -LiteralPath $backup -File | Where-Object { $_.Name -like 'ChromeProfileBackup.partial*' -and $others -notcontains $_.Name }) |
            Should -BeNullOrEmpty -Because 'the run removes or publishes its own partial zip'
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
        Mock New-ChromeBackupZip -ModuleName ChromeProfile {
            Set-Content -LiteralPath $ZipPath -Value 'partial'
            throw 'file locked'
        }

        $result = Backup-ChromeProfile -Destination $backup -ProfilePath $chromeProfile -ErrorVariable err -ErrorAction SilentlyContinue

        $result | Should -BeNullOrEmpty
        "$err" | Should -BeLike '*file locked*'
        (Get-FileHash -LiteralPath $first.FullName).Hash | Should -Be $before -Because 'a failed backup must not destroy the last good one'
        @(Get-ChildItem -LiteralPath $backup).Name | Should -Be @('ChromeProfileBackup.zip')
    }

    It 'writes an error and outputs nothing when the zip cannot be written' {
        Mock New-ChromeBackupZip -ModuleName ChromeProfile { throw 'disk full' }

        $result = Backup-ChromeProfile -Destination $backup -ProfilePath $chromeProfile -ErrorVariable err -ErrorAction SilentlyContinue

        $result | Should -BeNullOrEmpty
        "$err" | Should -BeLike '*Error backing up Chrome profile*disk full*'
    }

    It 'refuses an empty profile folder, keeping the previous backup zip unchanged' {
        $first = Backup-ChromeProfile -Destination $backup -ProfilePath $chromeProfile -ErrorAction Stop
        $before = (Get-FileHash -LiteralPath $first.FullName).Hash
        Get-ChildItem -LiteralPath $chromeProfile -Force | Remove-Item -Recurse -Force

        $result = Backup-ChromeProfile -Destination $backup -ProfilePath $chromeProfile -ErrorVariable err -ErrorAction SilentlyContinue

        $result | Should -BeNullOrEmpty
        "$err" | Should -BeLike '*holds no files*'
        (Get-FileHash -LiteralPath (Join-Path $backup 'ChromeProfileBackup.zip')).Hash | Should -Be $before -Because 'an emptied profile must not replace the last good backup'
        @(Get-ChildItem -LiteralPath $backup).Name | Should -Be @('ChromeProfileBackup.zip')
    }

    It 'refuses a profile that holds only empty folders' {
        $onlyDirs = Join-Path $root 'User Data/OnlyDirs'
        $null = New-Item -ItemType Directory -Path (Join-Path $onlyDirs 'a/b') -Force

        $result = Backup-ChromeProfile -Destination $backup -ProfilePath $onlyDirs -ErrorVariable err -ErrorAction SilentlyContinue

        $result | Should -BeNullOrEmpty
        "$err" | Should -BeLike '*holds no files*'
        Test-Path -LiteralPath (Join-Path $backup 'ChromeProfileBackup.zip') | Should -BeFalse
    }

    It 'writes an error and no partial zip when a folder named ChromeProfileBackup.zip is in the destination' {
        $null = New-Item -ItemType Directory -Path (Join-Path $backup 'ChromeProfileBackup.zip') -Force

        $result = Backup-ChromeProfile -Destination $backup -ProfilePath $chromeProfile -ErrorVariable err -ErrorAction SilentlyContinue

        $result | Should -BeNullOrEmpty
        "$err" | Should -BeLike '*folder named ChromeProfileBackup.zip*'
        @(Get-ChildItem -LiteralPath (Join-Path $backup 'ChromeProfileBackup.zip') -Force) | Should -BeNullOrEmpty -Because 'the partial zip must not be moved into the folder'
        @(Get-ChildItem -LiteralPath $backup -File -Force) | Should -BeNullOrEmpty
    }

    It 'refuses a -ProfilePath on a non-file-system provider' {
        $result = Backup-ChromeProfile -Destination $backup -ProfilePath 'Variable:\chromeProfile' -ErrorVariable err -ErrorAction SilentlyContinue

        $result | Should -BeNullOrEmpty
        "$err" | Should -BeLike '*not a file-system path*'
        Test-Path -LiteralPath $backup | Should -BeFalse
    }

    It 'refuses a -Destination on a non-file-system provider, writing nothing anywhere, process directory included' {
        $processDir = [System.Environment]::CurrentDirectory
        $strayName = 'psu-stray-' + [guid]::NewGuid().ToString('N')
        $variableDestination = 'Variable:\' + $strayName

        $result = Backup-ChromeProfile -Destination $variableDestination -ProfilePath $chromeProfile -ErrorVariable err -ErrorAction SilentlyContinue

        $result | Should -BeNullOrEmpty
        "$err" | Should -BeLike '*not a file-system path*'
        Test-Path -LiteralPath (Join-Path $processDir $strayName) | Should -BeFalse -Because 'no zip may land in the process working directory'
        Test-Path -LiteralPath (Join-Path (Get-Location).ProviderPath $strayName) | Should -BeFalse
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
        # Brackets in the path: must be used literally, not as a wildcard.
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

    It 'round-trips hidden files and folders and empty folders at any depth' {
        Initialize-FakeChromeProfile -Path $chromeProfile -Bookmarks 'saved'
        Add-HiddenProfileContent -Path $chromeProfile
        $null = Backup-ChromeProfile -Destination $backup -ProfilePath $chromeProfile -ErrorAction Stop
        Remove-Item -LiteralPath $chromeProfile -Recurse -Force

        $null = Restore-ChromeProfile -Path $backup -ProfilePath $chromeProfile -ErrorAction Stop

        Assert-FakeChromeProfile -Path $chromeProfile
        Assert-HiddenProfileContent -Path $chromeProfile
    }

    It 'round-trips through a bracketed backup folder and a bracketed profile, leaving look-alike folders alone' {
        $source = Join-Path $root 'User Data/Profile [1]'
        Initialize-FakeChromeProfile -Path $source -Bookmarks 'saved'
        $decoyBackup = Join-Path $root 'Backup 1'
        $null = New-Item -ItemType Directory -Path $decoyBackup -Force
        $bracketedBackup = Join-Path $root 'Backup [1]'
        $null = Backup-ChromeProfile -Destination $bracketedBackup -ProfilePath $source -ErrorAction Stop
        Remove-Item -LiteralPath $source -Recurse -Force
        $decoyProfile = Join-Path $root 'User Data/Profile 1'
        $null = New-Item -ItemType Directory -Path $decoyProfile -Force

        $null = Restore-ChromeProfile -Path $bracketedBackup -ProfilePath $source -ErrorAction Stop

        Get-Content -LiteralPath (Join-Path $source 'Bookmarks') | Should -Be 'saved'
        @(Get-ChildItem -LiteralPath $decoyProfile -Force) | Should -BeNullOrEmpty
        @(Get-ChildItem -LiteralPath $decoyBackup -Force) | Should -BeNullOrEmpty
    }

    It 'still restores a zip written by the previous (Compress-Archive) writer: contents at the zip root' {
        # The layout the old code produced: Compress-Archive of '<profile>/*' puts entries at the root.
        $legacySource = Join-Path $root 'old-src'
        $null = New-Item -ItemType Directory -Path (Join-Path $legacySource 'Extensions') -Force
        Set-Content -LiteralPath (Join-Path $legacySource 'Bookmarks') -Value 'old writer'
        Set-Content -LiteralPath (Join-Path $legacySource 'Extensions/marker.txt') -Value 'nested'
        $null = New-Item -ItemType Directory -Path $backup -Force
        Compress-Archive -Path (Join-Path $legacySource '*') -DestinationPath $zip -ErrorAction Stop

        $result = Restore-ChromeProfile -Path $backup -ProfilePath $chromeProfile -ErrorAction Stop

        $result | Should -BeOfType System.IO.DirectoryInfo
        Get-Content -LiteralPath (Join-Path $chromeProfile 'Bookmarks') | Should -Be 'old writer'
        Get-Content -LiteralPath (Join-Path $chromeProfile 'Extensions/marker.txt') | Should -Be 'nested'
        Test-Path -LiteralPath $zip | Should -BeFalse
    }

    It 'refuses a zip with an entry that escapes the profile folder (zip-slip), writing nothing and keeping the zip' {
        $null = New-Item -ItemType Directory -Path $backup -Force
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($name in 'Bookmarks', '../escaped.txt') {
                $writer = New-Object System.IO.StreamWriter(($archive.CreateEntry($name)).Open())
                try { $writer.Write('x') } finally { $writer.Dispose() }
            }
        }
        finally { $archive.Dispose() }

        $result = Restore-ChromeProfile -Path $backup -ProfilePath $chromeProfile -ErrorVariable err -ErrorAction SilentlyContinue

        $result | Should -BeNullOrEmpty
        "$err" | Should -BeLike '*outside the destination folder*'
        Test-Path -LiteralPath $zip | Should -BeTrue
        Test-Path -LiteralPath $chromeProfile | Should -BeFalse
        Test-Path -LiteralPath (Join-Path (Split-Path -Parent $chromeProfile) 'escaped.txt') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $root 'User Data/escaped.txt') | Should -BeFalse
    }

    It 'resolves a relative -ProfilePath and -Path against the PowerShell location, not the process directory' {
        Initialize-FakeChromeProfile -Path $chromeProfile -Bookmarks 'relative'
        $null = Backup-ChromeProfile -Destination $backup -ProfilePath $chromeProfile -ErrorAction Stop
        Remove-Item -LiteralPath $chromeProfile -Recurse -Force
        [System.Environment]::CurrentDirectory | Should -Not -Be (Get-Item -LiteralPath $root).FullName

        Push-Location $root
        try {
            $result = Restore-ChromeProfile -Path 'backup' -ProfilePath 'User Data/Default' -ErrorAction Stop
        }
        finally { Pop-Location }

        $result.FullName | Should -Be (Get-Item -LiteralPath $chromeProfile).FullName
        Get-Content -LiteralPath (Join-Path $chromeProfile 'Bookmarks') | Should -Be 'relative'
        Test-Path -LiteralPath (Join-Path ([System.Environment]::CurrentDirectory) 'User Data') | Should -BeFalse
    }

    It 'refuses a -ProfilePath or -Path on a non-file-system provider, writing nothing and keeping the zip' {
        Initialize-FakeChromeProfile -Path $chromeProfile
        $null = Backup-ChromeProfile -Destination $backup -ProfilePath $chromeProfile -ErrorAction Stop
        Remove-Item -LiteralPath $chromeProfile -Recurse -Force
        $processDir = [System.Environment]::CurrentDirectory
        $strayName = 'psu-stray-' + [guid]::NewGuid().ToString('N')

        $r1 = Restore-ChromeProfile -Path $backup -ProfilePath ('Variable:\' + $strayName) -ErrorVariable e1 -ErrorAction SilentlyContinue
        $r2 = Restore-ChromeProfile -Path ('Variable:\' + $strayName) -ProfilePath $chromeProfile -ErrorVariable e2 -ErrorAction SilentlyContinue

        $r1 | Should -BeNullOrEmpty
        $r2 | Should -BeNullOrEmpty
        "$e1" | Should -BeLike '*not a file-system path*'
        "$e2" | Should -BeLike '*not a file-system path*'
        Test-Path -LiteralPath $zip | Should -BeTrue
        Test-Path -LiteralPath $chromeProfile | Should -BeFalse
        @(Get-ChildItem -LiteralPath $processDir -Force | Where-Object { $_.Name -like "$strayName*" }) | Should -BeNullOrEmpty
        @(Get-ChildItem -LiteralPath (Get-Location).ProviderPath -Force | Where-Object { $_.Name -like "$strayName*" }) | Should -BeNullOrEmpty
    }

    It 'restores an empty folder, not an error, from a zip with no entries' {
        $null = New-Item -ItemType Directory -Path $backup -Force
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create).Dispose()

        $result = Restore-ChromeProfile -Path $backup -ProfilePath $chromeProfile -ErrorVariable err -ErrorAction SilentlyContinue

        "$err" | Should -BeNullOrEmpty
        $result | Should -BeOfType System.IO.DirectoryInfo
        @(Get-ChildItem -LiteralPath $chromeProfile -Force) | Should -BeNullOrEmpty
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

    It 'restores into a bracketed profile path literally, never into a profile the brackets match as a wildcard' {
        Initialize-FakeChromeProfile -Path $chromeProfile -Bookmarks 'saved'
        $null = Backup-ChromeProfile -Destination $backup -ProfilePath $chromeProfile -ErrorAction Stop
        # 'Profile [1]' read as a wildcard pattern matches the existing 'Profile 1'.
        $decoy = Join-Path $root 'User Data/Profile 1'
        $null = New-Item -ItemType Directory -Path $decoy -Force
        $bracketed = Join-Path $root 'User Data/Profile [1]'

        $result = Restore-ChromeProfile -Path $backup -ProfilePath $bracketed -ErrorAction Stop

        $result.FullName | Should -Be (Get-Item -LiteralPath $bracketed).FullName
        Get-Content -LiteralPath (Join-Path $bracketed 'Bookmarks') | Should -Be 'saved'
        Assert-FakeChromeProfile -Path $bracketed
        @(Get-ChildItem -LiteralPath $decoy -Force) | Should -BeNullOrEmpty -Because 'another profile must never receive the restore'
        Test-Path -LiteralPath $zip | Should -BeFalse
    }

    It 'never deletes or changes a profile that appears after the existence check' {
        Initialize-FakeChromeProfile -Path $chromeProfile -Bookmarks 'saved'
        $null = Backup-ChromeProfile -Destination $backup -ProfilePath $chromeProfile -ErrorAction Stop
        # Another process (Chrome starting) creates the profile between the check and the extraction:
        # the check is mocked to see no profile while one exists, with a file the zip also holds.
        Set-Content -LiteralPath (Join-Path $chromeProfile 'Bookmarks') -Value 'created by Chrome'
        $checkedPath = $chromeProfile
        Mock Test-Path -ModuleName ChromeProfile { Microsoft.PowerShell.Management\Test-Path @PesterBoundParameters }
        Mock Test-Path -ModuleName ChromeProfile -ParameterFilter { $LiteralPath -eq $checkedPath } { $false }

        $result = Restore-ChromeProfile -Path $backup -ProfilePath $chromeProfile -ErrorVariable err -ErrorAction SilentlyContinue

        $result | Should -BeNullOrEmpty
        "$err" | Should -BeLike '*Error restoring Chrome profile*'
        Get-Content -LiteralPath (Join-Path $chromeProfile 'Bookmarks') | Should -Be 'created by Chrome' -Because 'a profile this call did not create must be left as it is'
        Test-Path -LiteralPath $zip | Should -BeTrue
        @(Get-ChildItem -LiteralPath (Split-Path -Parent $chromeProfile) -Force | Where-Object Name -ne 'Default') | Should -BeNullOrEmpty -Because 'the temporary extraction folder is removed'
    }

    It 'restores to a profile path given with a trailing separator' {
        Initialize-FakeChromeProfile -Path $chromeProfile -Bookmarks 'saved'
        $null = Backup-ChromeProfile -Destination $backup -ProfilePath $chromeProfile -ErrorAction Stop
        Remove-Item -LiteralPath $chromeProfile -Recurse -Force
        $withSeparator = $chromeProfile + [System.IO.Path]::DirectorySeparatorChar

        $result = Restore-ChromeProfile -Path $backup -ProfilePath $withSeparator -ErrorAction Stop

        $result | Should -BeOfType System.IO.DirectoryInfo
        Get-Content -LiteralPath (Join-Path $chromeProfile 'Bookmarks') | Should -Be 'saved'
        @(Get-ChildItem -LiteralPath (Split-Path -Parent $chromeProfile) -Force).Name | Should -Be 'Default' -Because 'the staging folder is a sibling and is renamed into place'
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

Describe 'Expand-ChromeBackupZip' {
    It 'refuses an entry that lands in a sibling folder sharing the destination name as a prefix' {
        InModuleScope ChromeProfile -Parameters @{ Base = (Join-Path $TestDrive ([guid]::NewGuid().Guid)) } {
            param($Base)
            $null = New-Item -ItemType Directory -Path $Base -Force
            $zipPath = Join-Path $Base 'evil.zip'
            $destination = Join-Path $Base 'dest'
            Add-Type -AssemblyName System.IO.Compression
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $archive = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
            try {
                $writer = New-Object System.IO.StreamWriter(($archive.CreateEntry('../dest-evil/x')).Open())
                try { $writer.Write('x') } finally { $writer.Dispose() }
            }
            finally { $archive.Dispose() }

            { Expand-ChromeBackupZip -ZipPath $zipPath -DestinationPath $destination } | Should -Throw '*outside the destination folder*'

            Test-Path -LiteralPath (Join-Path $Base 'dest-evil') | Should -BeFalse
            Test-Path -LiteralPath $destination | Should -BeFalse
        }
    }
}

Describe 'Backup-ChromeBookmark' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        $chromeProfile = Join-Path $root 'User Data/Default'
        $backup = Join-Path $root 'backup'
        Initialize-FakeChromeProfile -Path $chromeProfile -Bookmarks 'first'
    }

    It 'copies Bookmarks to <Destination>/Chrome-Bookmarks, creating the folder' {
        $result = Backup-ChromeBookmark -Destination $backup -ProfilePath $chromeProfile

        $result | Should -BeOfType System.IO.FileInfo
        $result.FullName | Should -Be (Get-Item -LiteralPath (Join-Path $backup 'Chrome-Bookmarks')).FullName
        Get-Content -LiteralPath $result.FullName | Should -Be 'first'
    }

    It 'writes into a bracketed destination literally, never into a folder the brackets match as a wildcard' {
        $decoy = Join-Path $root 'Backup 1'
        $null = New-Item -ItemType Directory -Path $decoy -Force
        $bracketed = Join-Path $root 'Backup [1]'

        $result = Backup-ChromeBookmark -Destination $bracketed -ProfilePath $chromeProfile -ErrorAction Stop

        $result.FullName | Should -Be (Get-Item -LiteralPath (Join-Path $bracketed 'Chrome-Bookmarks')).FullName
        Get-Content -LiteralPath $result.FullName | Should -Be 'first'
        @(Get-ChildItem -LiteralPath $decoy -Force) | Should -BeNullOrEmpty -Because 'the look-alike folder must stay untouched'
    }

    It 'replaces an earlier copy on a second run' {
        $null = Backup-ChromeBookmark -Destination $backup -ProfilePath $chromeProfile
        Set-Content -LiteralPath (Join-Path $chromeProfile 'Bookmarks') -Value 'second'

        $result = Backup-ChromeBookmark -Destination $backup -ProfilePath $chromeProfile -ErrorVariable err

        $err | Should -BeNullOrEmpty
        Get-Content -LiteralPath $result.FullName | Should -Be 'second'
    }

    It 'reads the Default profile when no -ProfilePath is given, and accepts -BackupPath and the old name' {
        Mock Get-ChromeDefaultProfilePath -ModuleName ChromeProfile { $chromeProfile }

        $result = Backup-ChromeBookmarks -BackupPath $backup

        Get-Content -LiteralPath $result.FullName | Should -Be 'first'
        Should -Invoke Get-ChromeDefaultProfilePath -ModuleName ChromeProfile -Times 1 -Exactly
    }

    It 'requires a destination' {
        (Get-Command Backup-ChromeBookmark).Parameters['Destination'].Attributes.Mandatory | Should -Contain $true
    }

    It 'writes an error and creates nothing when the profile has no Bookmarks file' {
        Remove-Item -LiteralPath (Join-Path $chromeProfile 'Bookmarks')

        $result = Backup-ChromeBookmark -Destination $backup -ProfilePath $chromeProfile -ErrorVariable err -ErrorAction SilentlyContinue

        $result | Should -BeNullOrEmpty
        "$err" | Should -BeLike '*bookmarks file not found*'
        Test-Path -LiteralPath $backup | Should -BeFalse
    }

    It 'writes an error when the copy fails' {
        Mock Copy-Item -ModuleName ChromeProfile { throw 'access denied' }

        $result = Backup-ChromeBookmark -Destination $backup -ProfilePath $chromeProfile -ErrorVariable err -ErrorAction SilentlyContinue

        $result | Should -BeNullOrEmpty
        "$err" | Should -BeLike '*Error copying Chrome bookmarks*access denied*'
    }
}

Describe 'Restore-ChromeBookmark' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        $chromeProfile = Join-Path $root 'User Data/Default'
        $backup = Join-Path $root 'backup'
        Initialize-FakeChromeProfile -Path $chromeProfile -Bookmarks 'saved'
        $null = Backup-ChromeBookmark -Destination $backup -ProfilePath $chromeProfile
        Set-Content -LiteralPath (Join-Path $chromeProfile 'Bookmarks') -Value 'damaged'
    }

    It 'restores into a bracketed profile literally, never into a profile the brackets match as a wildcard' {
        $decoy = Join-Path $root 'User Data/Profile 1'
        $bracketed = Join-Path $root 'User Data/Profile [1]'
        foreach ($folder in $decoy, $bracketed) {
            $null = [System.IO.Directory]::CreateDirectory($folder)
            Set-Content -LiteralPath (Join-Path $folder 'Bookmarks') -Value 'untouched'
        }

        $null = Restore-ChromeBookmark -Path $backup -ProfilePath $bracketed -ErrorAction Stop

        Get-Content -LiteralPath (Join-Path $bracketed 'Bookmarks') | Should -Be 'saved'
        Get-Content -LiteralPath (Join-Path $decoy 'Bookmarks') | Should -Be 'untouched' -Because 'another profile must never receive the restore'
    }

    It 'replaces the profile Bookmarks file with the backup copy' {
        $result = Restore-ChromeBookmark -Path $backup -ProfilePath $chromeProfile

        $result | Should -BeOfType System.IO.FileInfo
        Get-Content -LiteralPath (Join-Path $chromeProfile 'Bookmarks') | Should -Be 'saved'
    }

    It 'writes to the Default profile when no -ProfilePath is given, and accepts -BackupPath and the old name' {
        Mock Get-ChromeDefaultProfilePath -ModuleName ChromeProfile { $chromeProfile }

        $null = Restore-ChromeBookmarks -BackupPath $backup

        Get-Content -LiteralPath (Join-Path $chromeProfile 'Bookmarks') | Should -Be 'saved'
    }

    It 'writes an error and changes nothing when the backup copy is missing' {
        $empty = Join-Path $root 'empty'

        $result = Restore-ChromeBookmark -Path $empty -ProfilePath $chromeProfile -ErrorVariable err -ErrorAction SilentlyContinue

        $result | Should -BeNullOrEmpty
        "$err" | Should -BeLike '*bookmarks backup not found*'
        Get-Content -LiteralPath (Join-Path $chromeProfile 'Bookmarks') | Should -Be 'damaged'
    }

    It 'writes an error and creates nothing when the profile folder is missing' {
        $missing = Join-Path $root 'User Data/Profile 9'

        $result = Restore-ChromeBookmark -Path $backup -ProfilePath $missing -ErrorVariable err -ErrorAction SilentlyContinue

        $result | Should -BeNullOrEmpty
        "$err" | Should -BeLike '*Chrome profile folder not found*'
        Test-Path -LiteralPath $missing | Should -BeFalse
    }

    It 'writes an error when the copy fails' {
        Mock Copy-Item -ModuleName ChromeProfile { throw 'file in use' }

        $null = Restore-ChromeBookmark -Path $backup -ProfilePath $chromeProfile -ErrorVariable err -ErrorAction SilentlyContinue

        "$err" | Should -BeLike '*Error restoring Chrome bookmarks*file in use*'
    }
}

Describe 'Get-ChromeExtension' {
    BeforeAll {
        function Add-FakeExtension {
            param([string]$Root, [string]$User, [string]$Id, [string]$Version, [string]$Json)
            $folder = [System.IO.Path]::Combine($Root, $User, 'AppData', 'Local', 'Google', 'Chrome', 'User Data', 'Default', 'Extensions', $Id, $Version)
            $null = New-Item -ItemType Directory -Path $folder -Force
            if ($Json) { Set-Content -LiteralPath (Join-Path $folder 'manifest.json') -Value $Json }
            Join-Path $folder 'manifest.json'
        }
    }

    BeforeEach {
        $usersRoot = Join-Path $TestDrive ([guid]::NewGuid().Guid)
        $alicePath = Add-FakeExtension -Root $usersRoot -User 'alice' -Id 'abc' -Version '1.0_0' -Json '{"name":"Alpha","version":"1.0","permissions":["tabs"]}'
        $bobPath = Add-FakeExtension -Root $usersRoot -User 'bob' -Id 'def' -Version '2.1_0' -Json '{"name":"Beta","version":"2.1"}'
        $null = Add-FakeExtension -Root $usersRoot -User 'bob' -Id 'ghi' -Version '0.1_0'
        $null = New-Item -ItemType Directory -Path (Join-Path $usersRoot 'carol') -Force
    }

    It 'outputs each manifest with its properties plus User and Path' {
        $result = @(Get-ChromeExtension -UserProfileRoot $usersRoot | Sort-Object name)

        $result.Count | Should -Be 2
        $result[0].name | Should -Be 'Alpha'
        $result[0].version | Should -Be '1.0'
        $result[0].permissions | Should -Be 'tabs'
        $result[0].User | Should -Be 'alice'
        $result[0].Path | Should -Be $alicePath
        $result[1].name | Should -Be 'Beta'
        $result[1].User | Should -Be 'bob'
        $result[1].Path | Should -Be $bobPath
    }

    It 'writes an error for a manifest that is not JSON and still outputs the others' {
        $null = Add-FakeExtension -Root $usersRoot -User 'alice' -Id 'bad' -Version '1.0_0' -Json 'not json {'

        $result = @(Get-ChromeExtension -UserProfileRoot $usersRoot -ErrorVariable err -ErrorAction SilentlyContinue)

        $result.Count | Should -Be 2
        "$err" | Should -BeLike '*Error reading Chrome extension manifest*bad*'
    }

    It 'skips users without Chrome or with an unreadable profile without an error' {
        $null = Get-ChromeExtension -UserProfileRoot $usersRoot -ErrorVariable err

        $err | Should -BeNullOrEmpty -Because 'carol has no Chrome folder'
    }

    It 'reads a BOM-less manifest with non-ASCII text as UTF-8' {
        # Built from code points so this file stays ASCII: 'Cafe' with e-acute, then a CJK character.
        $name = 'Caf' + [char]0x00E9 + ' ' + [char]0x6F22
        [System.IO.File]::WriteAllText($alicePath, ('{"name":"' + $name + '","version":"1.0"}'), (New-Object System.Text.UTF8Encoding($false)))

        $result = @(Get-ChromeExtension -UserProfileRoot $usersRoot | Where-Object User -eq 'alice')

        $result.Count | Should -Be 1
        $result[0].name | Should -Be $name
    }

    It 'enumerates the user profile root with -ErrorAction Ignore so an unreadable folder surfaces nothing' {
        # A Pester mock cannot reproduce how Ignore drops a cmdlet's error record (an error written
        # inside a mock still reaches -ErrorVariable), so assert the preference the real call gets.
        Mock Get-ChildItem -ModuleName ChromeProfile -ParameterFilter { $LiteralPath -eq $usersRoot } {
            Microsoft.PowerShell.Management\Get-ChildItem -LiteralPath $LiteralPath -Directory
        }

        $result = @(Get-ChromeExtension -UserProfileRoot $usersRoot -ErrorVariable err)

        $err | Should -BeNullOrEmpty
        $result.Count | Should -Be 2
        Should -Invoke Get-ChildItem -ModuleName ChromeProfile -ParameterFilter { $LiteralPath -eq $usersRoot -and $ErrorAction -eq 'Ignore' } -Times 1 -Exactly
    }

    It 'writes an error and outputs nothing when the root does not exist' {
        $result = Get-ChromeExtension -UserProfileRoot (Join-Path $usersRoot 'missing') -ErrorVariable err -ErrorAction SilentlyContinue

        $result | Should -BeNullOrEmpty
        "$err" | Should -BeLike '*User profile root not found*'
    }

    It 'searches $env:SystemDrive/Users when no root is given' {
        $saved = $env:SystemDrive
        try {
            $env:SystemDrive = $usersRoot
            $null = Add-FakeExtension -Root (Join-Path $usersRoot 'Users') -User 'dave' -Id 'xyz' -Version '3.0_0' -Json '{"name":"Gamma"}'

            $result = @(Get-ChromeExtension)

            $result.Count | Should -Be 1
            $result[0].User | Should -Be 'dave'
        }
        finally {
            $env:SystemDrive = $saved
        }
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
