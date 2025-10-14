function Get-ProcessBitness {
    [cmdletbinding()]
    param (
        [parameter(mandatory=$true)]
        [string[]]$Process
    )
    $Bitness = Get-Bitness
    foreach ($Proc in $Process) {
        if (Test-Process -Process $Proc) {
            $ProcessModules = Get-Process -Name $Proc -Module
            switch ($Bitness) {
                'x64' {
                    if ($ProcessModules.ModuleName -contains 'wow64.dll') {
                        Write-Verbose "Found wow64.dll module in $Proc - x86 process"
                        Write-Output 'x86'
                    }
                    else {
                        Write-Verbose "Did not find wow64.dll module in $Proc - x64 process"
                        Write-Output 'x64'
                    }
                }
                'x86' {
                    Write-Verbose 'x86 operating system detected.'
                    Write-Output 'x86'
                }
            }
        }
        else {
            Write-Warning "Unable to find process $Proc"
        }
    }
}