function Get-ShadowStorageMaxSize {
    <#
    .SYNOPSIS
        Returns the shadow storage maximum size of the system drive as a percentage and in GB.

    .DESCRIPTION
        Reads the Win32_Volume for the system drive ($env:SystemDrive) and the
        Win32_ShadowStorage association whose volume is that drive, and returns one object
        with Drive, MaxSpacePercent (MaxSpace as a percentage of the volume capacity) and
        MaxSpaceGB. Both numbers are rounded to two decimals. Read-only.

        A missing volume or shadow storage association, or a failed CIM query, is a
        terminating error.

        Formerly Scripts/FileSystem/GetSystemDriveShadowStorageMaxSize-Package.ps1, which
        is now a thin wrapper around this function. Win32_ShadowStorage cannot be read from
        32-bit PowerShell on 64-bit Windows ("Initialization failure"); the former script
        re-ran itself in the 64-bit Windows PowerShell (sysnative powershell.exe) for that
        reason. This function asks WMI for the 64-bit provider instead, so it answers in the
        calling process from either bitness and from PowerShell 7 as well.

    .EXAMPLE
        Get-ShadowStorageMaxSize

        Drive MaxSpacePercent MaxSpaceGB
        ----- --------------- ----------
        C:                 10      47.62

    .EXAMPLE
        $s = Get-ShadowStorageMaxSize; "$($s.MaxSpacePercent)|$($s.MaxSpaceGB)"

        Writes the pipe-delimited line the former deployment package wrote.

    .NOTES
        Windows only. Reading Win32_ShadowStorage normally requires administrator rights.
        Runs on Windows PowerShell 5.1 and PowerShell 7. Part of the StorageHealth module.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $drive = "$env:SystemDrive".TrimEnd('\')
    if (-not $drive) {
        throw 'The SystemDrive environment variable is not set.'
    }

    $volume = Get-CimInstance -ClassName Win32_Volume -Filter "DriveLetter='$drive'" -ErrorAction Stop | Select-Object -First 1
    if (-not $volume -or "$($volume.DeviceID)" -notmatch '\{([0-9A-Fa-f-]+)\}') {
        throw "Could not determine the shadow storage maximum size: no volume found for $drive."
    }
    $volumeGuid = $Matches[1]

    $storage = @(Get-ShadowCimInstance -ClassName Win32_ShadowStorage |
            Where-Object { "$($_.Volume.DeviceID)" -match [regex]::Escape($volumeGuid) }) | Select-Object -First 1
    if (-not $storage -or -not $volume.Capacity) {
        throw "Could not determine the shadow storage maximum size: no shadow storage association for $drive."
    }

    [pscustomobject]@{
        Drive           = $drive
        MaxSpacePercent = [math]::Round($storage.MaxSpace / $volume.Capacity * 100, 2)
        MaxSpaceGB      = [math]::Round($storage.MaxSpace / 1GB, 2)
    }
}
