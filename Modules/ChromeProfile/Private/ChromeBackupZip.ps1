# Recognizes a zip in the layout of the old Scripts/FileSystem/ChromeProfileBackup.ps1, shared by
# Backup-ChromeProfile (which must never write such a zip) and Restore-ChromeProfile (which refuses one).

function Test-ChromeLegacyBackupZip {
    <#
    .SYNOPSIS
        Reports whether a zip holds every entry under a ChromeProfileBackup folder.

    .DESCRIPTION
        The old ChromeProfileBackup.ps1 zipped a staging folder, so every entry of its zip sits
        under a ChromeProfileBackup root (Windows PowerShell 5.1 Compress-Archive writes '\'
        separators, PowerShell 7 writes '/'). Returns $true when the zip has at least one entry
        and every entry is under that root, otherwise $false. An empty zip is not legacy.
        Throws when the zip cannot be opened.

    .PARAMETER Path
        Literal file-system path of the zip.

    .EXAMPLE
        Test-ChromeLegacyBackupZip -Path 'C:\Users\a\ChromeBackup\ChromeProfileBackup.zip'

        Returns $true for a zip made by the old script.

    .NOTES
        Read-only. Internal to the ChromeProfile module; not exported.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entries = @($archive.Entries)
        if ($entries.Count -eq 0) { return $false }
        foreach ($entry in $entries) {
            if (-not ($entry.FullName.StartsWith('ChromeProfileBackup/', [System.StringComparison]::Ordinal) -or $entry.FullName.StartsWith('ChromeProfileBackup\', [System.StringComparison]::Ordinal))) {
                return $false
            }
        }
        return $true
    }
    finally {
        $archive.Dispose()
    }
}

function New-ChromeBackupZip {
    <#
    .SYNOPSIS
        Zips the contents of a folder, hidden files and empty folders included.

    .DESCRIPTION
        Writes a zip of the folder's contents with the entries at the zip root (no top-level
        folder named after the source), the layout Compress-Archive wrote for a 'folder\*' source.
        Uses System.IO.Compression.ZipFile, which takes literal paths (Compress-Archive treats
        '[' and ']' as wildcards) and includes hidden files, hidden folders and empty folders at
        every depth. Both paths are made absolute first, because .NET resolves a relative path
        against the process working directory, not the PowerShell location. Loads the assemblies,
        which Windows PowerShell 5.1 does not load on its own. Throws on failure.

    .PARAMETER SourcePath
        Literal path of the folder to zip.

    .PARAMETER ZipPath
        Literal path of the zip to create. Must not exist.

    .EXAMPLE
        New-ChromeBackupZip -SourcePath 'C:\Users\a\Profile [1]' -ZipPath 'C:\Backup\x.partial.zip'

        Zips the profile's contents to the zip root.

    .NOTES
        Internal to the ChromeProfile module; not exported.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$ZipPath
    )

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        [System.IO.Path]::GetFullPath($SourcePath),
        [System.IO.Path]::GetFullPath($ZipPath),
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false)
}

function Expand-ChromeBackupZip {
    <#
    .SYNOPSIS
        Extracts a zip into a new folder, refusing any entry that would land outside it.

    .DESCRIPTION
        Checks every entry first: an entry whose full path is not inside the destination folder
        (a '..' segment or an absolute path, "zip-slip") makes it throw before anything is
        written. Then extracts from the same open archive (so the zip cannot be swapped between
        the check and the extraction), which takes literal paths and restores hidden files and
        empty folders. The destination must not exist or must be
        empty: Windows PowerShell 5.1 (.NET Framework) has no overwrite overload, and the caller
        always extracts into a fresh staging folder. Both paths are made absolute first (.NET
        resolves a relative path against the process working directory). Throws on failure.

    .PARAMETER ZipPath
        Literal path of the zip.

    .PARAMETER DestinationPath
        Literal path of the folder to extract into.

    .EXAMPLE
        Expand-ChromeBackupZip -ZipPath 'C:\Backup\ChromeProfileBackup.zip' -DestinationPath 'C:\Staging'

        Extracts the zip into C:\Staging.

    .NOTES
        Internal to the ChromeProfile module; not exported.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ZipPath,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Path]::GetFullPath($ZipPath)
    $destination = [System.IO.Path]::GetFullPath($DestinationPath).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $prefix = $destination + [System.IO.Path]::DirectorySeparatorChar
    $comparison = if ([System.IO.Path]::DirectorySeparatorChar -eq '\') { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }

    # One open handle for the check and the extraction: OpenRead shares the file for reading
    # only, so it cannot be replaced between the two, and what is extracted is what was checked.
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
    try {
        foreach ($entry in $archive.Entries) {
            $relative = $entry.FullName.Replace('\', [string][System.IO.Path]::DirectorySeparatorChar).Replace('/', [string][System.IO.Path]::DirectorySeparatorChar)
            $full = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($destination, $relative))
            if (-not ($full.StartsWith($prefix, $comparison) -or $full.Equals($destination, $comparison))) {
                throw "zip entry '$($entry.FullName)' would be extracted outside the destination folder"
            }
        }
        # An entry-less zip makes ExtractToDirectory create nothing on .NET (Core); the caller
        # renames the folder into place, so it must exist.
        $null = [System.IO.Directory]::CreateDirectory($destination)
        [System.IO.Compression.ZipFileExtensions]::ExtractToDirectory($archive, $destination)
    }
    finally {
        $archive.Dispose()
    }
}

function Test-ChromeZipHasFile {
    <#
    .SYNOPSIS
        Reports whether a zip holds at least one file entry (not only folder entries).

    .DESCRIPTION
        A zip with no file entries holds no profile data. Backup-ChromeProfile uses this to
        refuse such a zip, so an empty profile folder never replaces a good backup.
        Throws when the zip cannot be opened.

    .PARAMETER Path
        Literal file-system path of the zip.

    .EXAMPLE
        Test-ChromeZipHasFile -Path 'C:\Backup\x.partial.zip'

        Returns $true when the zip has a file entry.

    .NOTES
        Read-only. Internal to the ChromeProfile module; not exported.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        foreach ($entry in $archive.Entries) {
            if ($entry.Name -ne '') { return $true }
        }
        return $false
    }
    finally {
        $archive.Dispose()
    }
}
