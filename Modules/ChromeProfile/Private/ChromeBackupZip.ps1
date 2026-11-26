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
