$paths = "C:\Program Files (x86)\Hyland\Office Integration\Office 2016", "C:\Program Files\Hyland\Office Integration\Office 2016"
foreach ($path in $paths) {
    if (Test-Path $path) {
        try {
            $targetFile = Get-ChildItem -Path $path -Filter "Hyland.Office2016.Outlook.Addin.dll.config"
            $report = @()
            foreach ( $f in $targetFile ) {
                $content = Get-Content -Path $f.FullName -Raw
                if ($content -match '<RetrievalButton>true</RetrievalButton>') {
                    $content.Replace('<RetrievalButton>true</RetrievalButton>', '<RetrievalButton>false</RetrievalButton>') | Set-Content -Path $f.FullName -Force
                    #Write-Output "$($f.Name): Applied changes"
                    $result = 'Applied changes'
                }
                else {
                    #Write-Output "$($f.Name): No changes required"
                    $result = 'No changes required'
                }
                $obj = [PSCustomObject]@{
                    computerName = $env:COMPUTERNAME
                    fileName     = $f.Name
                    result       = $result
                }
                $report += $obj
            }
            $report
        }
        catch {
            Write-Error $_.exception
        }
    }
}