<#
.SYNOPSIS
Reports whether the local operating system is 64-bit or 32-bit.

.DESCRIPTION
Reads the Win32_Processor class (root/cimv2) with Get-CimInstance, takes the
AddressWidth of the processor whose DeviceID is CPU0, and writes one string to the
output: AMD64 when the width is 64, x86 when it is 32, and Unknown for any other
value (including when no CPU0 instance is returned). It changes nothing.

The script defines the Get-OSArchitecture function and then calls it, so running
the file produces the result directly.

.EXAMPLE
.\Get-OSArchitecture.ps1

AMD64

.NOTES
Requires Windows and the CIM cmdlets (Windows PowerShell 3.0 or later, or
PowerShell 7 on Windows). No admin rights needed.

AddressWidth reports the width the operating system runs at, so a 32-bit Windows
on a 64-bit processor reports x86. A 64-bit ARM system would also report AMD64,
because only the address width is checked.

If the CIM query fails, the function throws a terminating error. It ends the
script, not the PowerShell session; run with powershell.exe -File, the process
exit code is 1.
#>


function Get-OSArchitecture {
    <#
    .SYNOPSIS
    Gets the Operating System architecture
    
    .DESCRIPTION
    Query WMI to determine OS Architecture, returning a string value of AMD64 or x86
    
    .EXAMPLE
    Get-OSArchitecture
    
    .OUTPUTS
    [string]

    .NOTES
    Created on 2019-04-11 by Jesse S.

    #>
    
    Process {
        Try {
            $Processor = Get-CimInstance -Namespace Root/cimv2 -ClassName Win32_Processor -ErrorAction Stop
            $Architecture = ($Processor | Where-Object { $_.deviceID -eq "CPU0" }).AddressWidth
            Switch ($Architecture) {
                64 {
                    'AMD64'
                }
                32 {
                    'x86'
                }
                default {
                    'Unknown' 
                }
            }
        }    
        Catch {
            # Rethrow rather than [Environment]::Exit, which would end the whole
            # PowerShell process (and the caller's session) instead of this script.
            throw
        }
    }
}

Get-OSArchitecture