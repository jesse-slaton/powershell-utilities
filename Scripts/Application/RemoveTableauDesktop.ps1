[String]$ParamString  = [System.Uri]::UnescapeDataString($args[0])
$UninstallString = $ParamString.Replace(' /modify','')
$Arguments = "/uninstall /quiet"

$Uninstaller = start-process -FilePath $UninstallString -ArgumentList $Arguments -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue -PassThru
switch ($Uninstaller.ExitCode) {
    {0,1605,3010} {
        write-host "Removed Tableau Desktop"
    }
    default {
        $Host.SetShouldExit(1)
    }
}