<#
.SYNOPSIS
    Turns off the Retrieval button of the Hyland OnBase Outlook add-in for Office 2016.

.DESCRIPTION
    Looks in "C:\Program Files (x86)\Hyland\Office Integration\Office 2016" and
    "C:\Program Files\Hyland\Office Integration\Office 2016" for
    Hyland.Office2016.Outlook.Addin.dll.config. When a file contains
    <RetrievalButton>true</RetrievalButton>, that text is replaced with
    <RetrievalButton>false</RetrievalButton> and the file is rewritten with Set-Content.

    For each file found, outputs an object with computerName, fileName and result
    ("Applied changes" or "No changes required"). Folders that do not exist are skipped
    without output. An error while reading or writing is written with Write-Error.

    The check (-match) is case-insensitive but the replacement is case-sensitive, so a
    file containing, for example, <RetrievalButton>True</RetrievalButton> is reported as
    "Applied changes" but keeps its value.

.EXAMPLE
    .\Set-OneBaseRetrievalButtonValue.ps1

    Updates the add-in config where needed and outputs one result object per file found.

.NOTES
    Requires administrator rights (the files are under Program Files) and the Hyland
    OnBase Office Integration for Office 2016. Set-Content writes the file in the
    default encoding of the running PowerShell edition, which can differ from the
    original file's encoding.
#>
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