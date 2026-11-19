<#
.SYNOPSIS
    Checks that the Avaya Agent for Desktop config-spec.xml matches a known SHA-256 hash.

.DESCRIPTION
    Hashes C:\Program Files\Avaya\Avaya Agent\config\config-spec.xml with Get-FileHash
    and compares it to a hash embedded in the script. Exits with code 0 when the file
    exists and matches, and 99 otherwise (missing file or different content). Writes no
    output; intended as a deployment-tool detection script that reads the exit code.

.EXAMPLE
    .\Test-AAfDConfigFile.ps1; $LASTEXITCODE

    0

.NOTES
    Requires Avaya Agent for Desktop installed in the default location. No admin rights
    needed to read the file. Update the embedded hash when the expected config changes.
#>
$ConfigFile = 'C:\Program Files\Avaya\Avaya Agent\config\config-spec.xml'
$SHA256Hash = 'bb28533ee5e3950a7eef4013ddca693519f5c6cebe8bdb5cc5df19f5c3287294'
$ReturnCode = 99
If (Test-Path -Path "$ConfigFile") {
    If ((Get-FileHash -Path $Configfile).Hash -match $SHA256Hash) {
        $ReturnCode = 0
    }
}
Exit $ReturnCode