#requires -Version 2

Function Invoke-VBScript {
    <#
    .Synopsis
       Run VBScript from PowerShell
    .DESCRIPTION
       Used to invoke VBScript from PowerShell

       Will run the VBScript in a separate job using cscript.exe
    .PARAMETER Path
       Path to VBScript.
       Accepts relative or absolute path.
    .PARAMETER Argument
       Arguments to pass to VBScript
    .PARAMETER Wait
       Wait for VBScript to finish   
    .EXAMPLE
       Invoke-VBScript -Path '.\VBScript1.vbs' -Arguments '"MyFirstArgument"', '"MySecondArgument"' -Wait
       Run VBScript1.vbs using cscript and wait for the script to complete.
       Displays progressbar while waiting.
       Returns script output as single string.
    .EXAMPLE
       '.\VBScript1.vbs', '.\VBScript2.vbs' | Invoke-VBScript -Arguments '"MyArgument"'
       Starts both VBScript1.vbs and VBScript2.vbs in separate jobs simultaneously.
       Both scripts will be run using the same arguments.
       Returns job items.
    .EXAMPLE
       [PSCustomObject]@{Path='.\VBScript1.vbs';Arguments='"Script1"'},[PSCustomObject]@{Path='.\VBScript2.vbs';Arguments='"Script2"'} | Invoke-VBScript -Wait -Verbose
       Runs two scripts after each other, waiting to one to complete
       before starting next.
       Each script will run with different parameters.
       Displays progressbar while waiting.
       Returns script output in one single string per script.
    .NOTES
       Written by Simon Wåhlin
       http://blog.simonw.se
    #>
    [cmdletbinding(SupportsShouldProcess=$true,ConfirmImpact='None',PositionalBinding=$false)]
    Param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,Position=0)]
        [ValidateScript({if(Test-Path $_){$true}else{Throw "Could not find script: [$_]"}})]
        [String]
        $Path,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [Alias('Args')]
        [String[]]
        $Argument,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [Switch]
        $Wait
    )
    Begin
    {
        Write-Verbose -Message 'Locating cscript.exe'
        $cscriptpath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\cscript.exe'
        if(-Not(Test-Path -Path $cscriptpath))
        {
            Throw 'cscript.exe not found.'
        }
        Write-Verbose -Message ('cscript.exe found in: {0}' -f $cscriptpath)
    }
    Process
    {
        Try
        {
            $ResolvedPath = Resolve-Path -Path $Path
            Write-Verbose -Message ('Processing script: {0}' -f $ResolvedPath)
            if($PSBoundParameters.ContainsKey('Argument'))
            {
                $ScriptBlock = [scriptblock]::Create(('& "{0}" "{1}" "{2}"' -f $cscriptpath, $ResolvedPath,($Argument -join '" "')))
            }
            else
            {
                $ScriptBlock = $ScriptBlock = [scriptblock]::Create(('& "{0}" "{1}"' -f $cscriptpath, $ResolvedPath))
            }
            Write-Verbose -Message 'Starting script'
            if($PSCmdlet.ShouldProcess($ResolvedPath,'Invoke script'))
            {
                $Job = Start-Job -ScriptBlock $ScriptBlock
                if($Wait)
                {
                    $Activity = 'Waiting for script to complete: {0}' -f $ResolvedPath
                    Write-Progress -Activity $Activity -Id 1
                    $i = 1
                    While($Job.State -eq 'Running')
                    {
                        $WaitTime = (Get-Date) - $Job.PSBeginTime
                        Write-Progress -Activity $Activity -Status "Waited for $($WaitTime.TotalSeconds -as [int]) seconds." -Id 1 -PercentComplete ($i%100)
                        Start-Sleep -Seconds 1
                        $i++
                    }
                    Write-Progress -Activity $Activity -Status 'Waiting' -Id 1 -Completed
                    $Result = Foreach($JobInstance in ($Job,$Job.ChildJobs))
                    {
                        if($JobInstance.Error -ne $null)
                        {
                            Throw $JobInstance.Error.Exception.Message
                        }
                        else
                        {
                            $JobInstance.Output
                        }
                    }
                    Write-Output -InputObject ($Result -join "`n")
                    Remove-Job -Job $Job -Force -ErrorAction SilentlyContinue
                }
                else
                {
                    Write-Output -InputObject $Job
                }
            }
            Write-Verbose -Message 'Finished processing script'
        }
        Catch
        {
            Throw
        }
    }
}

