#Requires -Version 7.0

<#
.SYNOPSIS
    Samples CPU load on a set of Active Directory computers and outputs an average per computer.

.DESCRIPTION
    Gets the AD computers whose name matches 'txsatr*' (hard-coded filter), resolves each
    DNSHostName with Resolve-DnsName, and keeps the names that answer one ping
    (Test-Connection). For each reachable computer, in parallel, it reads the average
    Win32_Processor LoadPercentage over CIM 11 times, 10 seconds apart, and divides the
    total by 10. Because 11 samples are divided by 10, the reported value is about 10
    percent higher than the true mean of the samples.

    For each computer it outputs two objects: the string "<ComputerName>," and the
    numeric average. Read-only. A run takes roughly two minutes per batch of computers
    (ForEach-Object -Parallel default throttle of 5).

.EXAMPLE
    .\Get-LoadAvg.ps1

    Outputs "<ComputerName>," followed by its average load for each reachable computer.

.EXAMPLE
    .\Get-LoadAvg.ps1 | Out-File .\loadavg.txt

    Saves the results to a text file.

.NOTES
    Requires PowerShell 7 (#Requires -Version 7.0; uses ForEach-Object -Parallel), the
    ActiveDirectory module (RSAT) and the DnsClient module. Needs network access to a
    domain controller and to the target computers, ICMP allowed, and CIM/WinRM access
    with rights to query Win32_Processor on them (normally administrator).
#>
$GADCFilter = "Name -like 'txsatr*'"
$ADTrComps = (Get-ADComputer -Filter $GADCFilter | `
        Select-Object -ExpandProperty DNSHostName | `
        ForEach-Object { Resolve-DnsName $_ | `
            Select-Object -Property Name -Unique })

$TRComps = @()
$TRComps += $ADTrComps | ForEach-Object -parallel { If (Test-Connection $_.name -Quiet -Count 1) { $_.Name } }

$MachineAverage = $TRComps | ForEach-Object -parallel {
    $i = 0
    $Iterations = 10
    $LoadAccumulator = 0
    Do {
        #Write-Host $_.Name
        $LoadPercentageAverage = (Get-CimInstance -Namespace Root\Cimv2 -ClassName win32_processor -ComputerName $_ | `
                Measure-Object -property LoadPercentage -Average).Average.ToString()
        $LoadAccumulator += $LoadPercentageAverage
        Start-Sleep 10
        $i++
    }
    while ($i -le $Iterations)
    $LoadPercentageAverageAverage = $LoadAccumulator / $Iterations
    Write-Output $_"," $LoadPercentageAverageAverage
}
$MachineAverage