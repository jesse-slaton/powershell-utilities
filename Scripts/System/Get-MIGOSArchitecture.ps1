function GetMIGOSArchitecture {
    <#
    .SYNOPSIS
    Gets the Operating System architecture
    
    .DESCRIPTION
    Query WMI to determine OS Architecture, returning a string value of AMD64 or x86
    
    .EXAMPLE
    Get-MIGOSArchitecture
    
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
            Write-Error $_.Exception.Message
            [Environment]::Exit($_.Exception.HResult)   
        }
    }
}

GetMIGOSArchitecture