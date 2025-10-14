function Colorize-MsiLog {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [string]$Log
    )
    
    Begin {
        $ColorMap = @{
            "Verbose" = "Gray"
            "Debug" = "DarkGray"
            "Info" = "White"
            "Warning" = "Yellow"
            "Error" = "Red"
        }
    }
    
    Process {
        $Log -split "`n" | ForEach-Object {
            if ($_ -match '^(?<level>\w+)\s+') {
                $level = $Matches['level']
                $color = $ColorMap[$level]
                if ($color) {
                    Write-Host $_ -ForegroundColor $color
                } else {
                    Write-Host $_
                }
            } else {
                Write-Host $_
            }
        }
    }
    
    End {}
}

Export-ModuleMember -Function Colorize-MsiLog
