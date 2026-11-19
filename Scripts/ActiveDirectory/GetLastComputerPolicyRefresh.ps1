<#
.SYNOPSIS
    Reports how long ago Group Policy last finished processing for the computer.

.DESCRIPTION
    Reads the endTimeHi and endTimeLo values of the core Group Policy extension state
    key (HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\
    Extension-List\{00000000-0000-0000-0000-000000000000}), combines them into a
    file time, and writes the time elapsed since then as text:

    - "Less than 1 hour", "1 hour" or "<n> hours" when it was under a day ago
    - "Over 1 year" when it was 365 days or more ago
    - otherwise a string built from "($diff.days) days"; because only $diff is expanded
      inside the string, this shows the whole time span followed by ".days) days"
      rather than a day count
    - "Could not get last GPUpdate datetime" if the registry values cannot be read or
      converted

    Read-only.

.EXAMPLE
    .\GetLastComputerPolicyRefresh.ps1

    3 hours

.NOTES
    The code runs through Invoke-Command -ComputerName ., which needs PowerShell
    remoting (WinRM) enabled on the local computer and normally administrator rights.
#>
Invoke-Command -ScriptBlock {
    $Today = Get-Date
    Try {
        $RegPath = "Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\Extension-List\{00000000-0000-0000-0000-000000000000}"
        $endTimeHi = (Get-ItemProperty -Path "$RegPath").endTimeHi
        $endTimeLo = (Get-ItemProperty -Path "$RegPath").endTimeLo
        $gpDateTime = [datetime]::FromFileTime(([Int64] $endTimeHi -shl 32) -bor $endTimeLo)
        $Diff = (New-TimeSpan -Start $gpDateTime -End $Today)
        Switch ($Diff.days) {
            0 {
                Switch ($Diff.Hours) {
                    0 { $Output = "Less than 1 hour" }
                    1 { $Output = "$($Diff.Hours) hour" }
                    { $_ -gt 1 -and $_ -le 23 } { $Output = "$($Diff.Hours) hours" }
                } 
            }
            { $_ -ge 365 } { $Output = 'Over 1 year' }
            default { $Output = "($diff.days) days" }
            $null { $Output = 'Could not get last GPUpdate datetime.' }
        }
        #$Output = (Get-Date -f "ddd, dd MMM yyyy HH:mm zzz" $gpDateTime) -replace '(.*)(\+|\-)([0-9][0-9]):([0-9][0-9])', '$1$2$3$4'
    }
    Catch { 
        $Output = 'Could not get last GPUpdate datetime' 
    }
    Write-Output $Output
} -ComputerName .