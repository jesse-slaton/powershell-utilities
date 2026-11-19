<#
.SYNOPSIS
    Turns on System Restore for the system drive and caps its shadow storage at 10 percent.

.DESCRIPTION
    Runs Enable-ComputerRestore for $env:SystemDrive, then runs
    vssadmin resize ShadowStorage for the same drive with /MaxSize=10%. Writes the
    vssadmin output to the console.

.EXAMPLE
    .\EnableSystemDriveSystemRestore.ps1

    Enables System Restore on C: (typically) and limits its shadow storage to 10% of the drive.

.NOTES
    Requires administrator rights and Windows PowerShell 5.1 (Enable-ComputerRestore is
    not available in PowerShell 7). Changes system configuration.
#>
$SystemDrive = $Env:SystemDrive
Enable-ComputerRestore -Drive $SystemDrive
vssadmin.exe resize ShadowStorage /For=$SystemDrive /On=$SystemDrive /MaxSize=10%