<#
.SYNOPSIS
    Template that relaunches itself in 64-bit Windows PowerShell when started from 32-bit PowerShell on 64-bit Windows.

.DESCRIPTION
    If $env:PROCESSOR_ARCHITEW6432 is AMD64 (a 32-bit PowerShell process on 64-bit
    Windows), the script writes a warning and starts
    $env:WINDIR\sysnative\windowspowershell\v1.0\powershell.exe with -NonInteractive
    -NoProfile. It passes either the original invocation line ($MyInvocation.Line) or,
    when that is empty, -File with the script path and its arguments, then exits with
    the child's exit code. In a 64-bit (or 32-bit-only) process it runs the main body,
    which only writes "Main script body" and $env:PROCESSOR_ARCHITECTURE to the host.
    Replace the main body with the real work; the original header says the relaunch
    was needed for OleDb access. Makes no changes.

.EXAMPLE
    .\ArchTest-Package.ps1

    From 64-bit PowerShell, writes "Main script body" and AMD64. From 32-bit
    PowerShell on 64-bit Windows, relaunches in 64-bit and the child writes the same.

.NOTES
    Windows PowerShell only (the relaunch target is Windows PowerShell 5.1 under
    sysnative, which exists only for 32-bit processes on 64-bit Windows). Only AMD64 is
    detected, not ARM64. No admin rights needed.
#>

####################################################
# 32-bit-Test.ps1
# Created: 03/20/2013
# Author: me
# Summary: This script will test if Powershell is 
#          running in 32-bit mode and if true
#          launch itself in 64-bit mode for completion
####################################################
 
########################################################################################################
#If Powershell is running the 32-bit version on a 64-bit machine, we need to force powershell to run in
#64-bit mode to allow the OleDb access to function properly.
########################################################################################################
if ($env:PROCESSOR_ARCHITEW6432 -eq "AMD64") {
    write-warning "Y'arg Matey, we're off to 64-bit land....."
    if ($myInvocation.Line) {
        &"$env:WINDIR\sysnative\windowspowershell\v1.0\powershell.exe" -NonInteractive -NoProfile $myInvocation.Line
    }else{
        &"$env:WINDIR\sysnative\windowspowershell\v1.0\powershell.exe" -NonInteractive -NoProfile -file "$($myInvocation.InvocationName)" $args
    }
exit $lastexitcode
}
 
 
write-host "Main script body"
Write-Host $env:PROCESSOR_ARCHITECTURE
 
################
# END
################