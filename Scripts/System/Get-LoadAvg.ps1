#Requires -Version 7.0
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