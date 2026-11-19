function Colorize-MsiLog {
    <#
    .SYNOPSIS
        Writes text to the console, coloring each line by its leading level word.

    .DESCRIPTION
        Splits each Log string on newlines and writes every line with Write-Host. A
        line whose first word (letters, digits or underscore, followed by whitespace)
        is Verbose, Debug, Info, Warning or Error is written in Gray, DarkGray, White,
        Yellow or Red respectively; any other line is written in the default color.
        Writes to the host only and outputs nothing to the pipeline.

        Standard Windows Installer log lines start with text such as "MSI (s)" or
        "Action", not with these level words, so most lines of a normal MSI log are
        written uncolored.

    .PARAMETER Log
        Text to write. Accepts pipeline input; each string may contain several lines.

    .EXAMPLE
        Get-Content -Path 'C:\Temp\install.log' | Colorize-MsiLog

        Writes install.log to the console, one line at a time.

    .EXAMPLE
        Colorize-MsiLog -Log "Error something failed`nInfo done"

        Writes "Error something failed" in red and "Info done" in white.

    .NOTES
        None. Colorize is not an approved verb, so Import-Module warns about it.
    #>
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
