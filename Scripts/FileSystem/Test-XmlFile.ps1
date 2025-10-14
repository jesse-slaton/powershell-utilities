function Test-XmlFile {
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
                $XmlFile = Read-XmlFile $File
                if ($XmlFile) {
                    Write-Verbose "$File is a valid xml file"
                    Write-Output $true
                }
                else {
                    Write-Verbose "$File is not a valid xml file"
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