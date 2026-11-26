function Enable-SystemDriveRestore {
    <#
    .SYNOPSIS
        Turns on System Restore for the system drive and caps its shadow storage at 10 percent.

    .DESCRIPTION
        Calls the Enable method of the root/default SystemRestore CIM class for the system
        drive ($env:SystemDrive, for example C:\) and waits until it is enabled, then runs
        vssadmin resize ShadowStorage for the same drive with /MaxSize=10%. Returns the
        vssadmin output lines. Changes system configuration.

        A non-zero return value from SystemRestore.Enable throws before vssadmin runs. A
        vssadmin failure (a non-zero exit code or an "Error:" line in its output) throws too.
        Supports -WhatIf and -Confirm.

        Formerly Scripts/Backup/EnableSystemDriveSystemRestore.ps1, which used
        Enable-ComputerRestore. That cmdlet does not exist in PowerShell 7; the CIM method it
        wrapped is called directly instead, so this runs on Windows PowerShell 5.1 and
        PowerShell 7.

    .EXAMPLE
        Enable-SystemDriveRestore

        Enables System Restore on the system drive and limits its shadow storage to 10% of
        the drive.

    .EXAMPLE
        Enable-SystemDriveRestore -WhatIf

        Shows what would change without changing anything.

    .NOTES
        Windows client editions only (the SystemRestore class does not exist on Windows
        Server). Requires administrator rights and vssadmin.exe. Runs only in 64-bit
        PowerShell: vssadmin.exe is not visible to a 32-bit process on 64-bit Windows, so from
        32-bit PowerShell this throws before changing anything. Part of the StorageHealth
        module.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([string])]
    param()

    $drive = $env:SystemDrive
    if (-not $drive) {
        throw 'The SystemDrive environment variable is not set.'
    }
    $drive = $drive.TrimEnd('\')
    $root = $drive + '\'

    # Checked before any change: otherwise System Restore is enabled and only the vssadmin step fails.
    if (Test-Wow64Process) {
        throw 'Enable-SystemDriveRestore must run in 64-bit PowerShell: vssadmin.exe is not available to a 32-bit process on 64-bit Windows.'
    }

    if ($PSCmdlet.ShouldProcess($root, 'Enable System Restore and cap shadow storage at 10%')) {
        $result = Invoke-CimMethod -Namespace 'root/default' -ClassName 'SystemRestore' -MethodName 'Enable' `
            -Arguments @{ Drive = $root; WaitTillEnabled = $true } -ErrorAction Stop
        if ($result.ReturnValue -ne 0) {
            throw "SystemRestore.Enable failed for $root with return value $($result.ReturnValue)."
        }

        Invoke-VssAdmin -ArgumentList @('resize', 'ShadowStorage', "/For=$drive", "/On=$drive", '/MaxSize=10%') -ErrorAction Stop
    }
}
