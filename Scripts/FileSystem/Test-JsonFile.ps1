function Test-JsonFile {
    [cmdletbinding()]
    param (
        [alias('FullName')]
        [parameter(Mandatory = $true,
            ValueFromPipelineByPropertyName = $true)]
        [string[]]$Path
    )
    begin {}
    process {
        foreach ($File in $Path) {
            if (Test-Path $File) {
                try {
                    $JsonFile = Get-Content -Path $File | ConvertFrom-Json -ErrorAction Stop
                    if ($JsonFile) {
                        Write-Verbose "$File is a valid json file"
                        Write-Output $true
                    }
                }
                catch {
                    Write-Verbose "$File is not a valid json file"
                    Write-Output $false
                }
            }
            else {
                Write-Warning "$File does not exist"
            }
        }
    }
    end {}
}