function Test-Command {
    [CmdletBinding()]
    param (
        [string]$Name
    )
    try {
        $CommandExists = Get-Command -Name $Name -ErrorAction Stop
        if ($CommandExists) {
            Write-Output $true
        }
    }
    catch {
        Write-Warning "Unable to find command $Name"
        Write-Output $false
    }
}