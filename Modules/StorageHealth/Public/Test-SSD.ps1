function Test-SSD {
    <#
    .SYNOPSIS
        Returns $true when a physical disk is a solid state disk (SSD), $false otherwise.

    .DESCRIPTION
        Reads two properties of \\.\PhysicalDrive<PhysicalDiskId> through kernel32
        DeviceIoControl calls: the nominal media rotation rate (ATA IDENTIFY DEVICE) and the
        seek penalty (IOCTL_STORAGE_QUERY_PROPERTY). Returns $true when the disk reports no
        rotation rate or no seek penalty, and $false when it reports both. When one call
        fails, that check counts as "spinning disk" and the result depends on the other
        check; the failure is written to the verbose stream. Read-only.

        Accepts disk numbers from the pipeline, for example from Get-PhysicalDisk.

        Formerly Scripts/System/TestSSD.ps1. It also supersedes Scripts/System/DetectSSD.ps1,
        which compiled the same two checks but never ran them.

    .PARAMETER PhysicalDiskId
        The physical disk number (the N in \\.\PhysicalDriveN), as in the DeviceId of
        Get-PhysicalDisk.

    .EXAMPLE
        Get-PhysicalDisk | Select-Object -ExpandProperty DeviceId | Test-SSD

        Tests every physical disk on the local computer.

    .EXAMPLE
        if (Test-SSD -PhysicalDiskId 0) { $delay = 0 }

        Sets $delay to 0 when the first physical disk is an SSD.

    .NOTES
        Windows only. The rotation-rate check opens the drive for read and write and needs
        administrator rights; without them only the seek-penalty check decides. Runs on
        Windows PowerShell 5.1 and PowerShell 7. Part of the StorageHealth module.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true, Position = 0)]
        [int]$PhysicalDiskId
    )

    process {
        $driveString = '\\.\PhysicalDrive' + $PhysicalDiskId
        Write-Verbose -Message "Current disk string is: $driveString"

        # Reset for every disk, so a skipped (-WhatIf) or failed check never reuses the
        # previous disk's answer.
        $hasRotationRate = $true
        $hasSeekPenalty = $true

        if ($PSCmdlet.ShouldProcess("Physical Disk $PhysicalDiskId", 'Read Nominal Media Rotation Rate Property')) {
            try {
                $hasRotationRate = Invoke-SsdNativeCheck -Check HasNominalMediaRotationRate -DriveString $driveString
            }
            catch {
                Write-Verbose -Message "HasNominalMediaRotationRate detection failed: $($_.Exception.Message)"
                $hasRotationRate = $true
            }
        }

        if ($PSCmdlet.ShouldProcess("Physical Disk $PhysicalDiskId", 'Read Seek Penalty Property')) {
            try {
                $hasSeekPenalty = Invoke-SsdNativeCheck -Check HasSeekPenalty -DriveString $driveString
            }
            catch {
                Write-Verbose -Message "HasSeekPenalty detection failed: $($_.Exception.Message)"
                $hasSeekPenalty = $true
            }
        }

        (-not $hasRotationRate) -or (-not $hasSeekPenalty)
    }
}
