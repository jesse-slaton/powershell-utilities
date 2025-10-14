#User Modifiable Variables
$InstallPaths = @("C:\Program Files\ibm\cognos\IBM for Microsoft Office", `
        "C:\Program Files (x86)\ibm\cognos\IBM for Microsoft Office")         
$Uninstaller = "uninst.exe"
$SystemStartMenu = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs"
$SystemStartMenuFolders = "IBM Planning Analytics for Microsoft Office"
$Arguments = "-u -s"
$UninstallLog = "$Env:TEMP\cognos_uninst_log.txt"

# DO NOT MODIFY BELOW THIS LINE

Function Get-FileStatus([string]$Path) {
    Try {
        $File = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, `
                [System.IO.FileAccess]::ReadWrite, `
                [System.IO.FileShare]::None
        )
        return $false
        $File.Close()
    }
    Catch {
        return $true
        $File.Close()
    }
} #End Function Get-FileStatus

ForEach ($InstallPath in $InstallPaths) {
    If (Test-Path -Path $InstallPath) {
        Start-Process -FilePath "$InstallPath\uninstall\$Uninstaller" `
            -ArgumentList $Arguments -ErrorAction SilentlyContinue `
            -PassThru -Wait -WindowStyle Hidden | Out-Null
        Get-FileStatus -Path $UninstallLog | Out-Null
        # $LogEntries = New-Object -TypeName System.IO.StreamReader -ArgumentList $UninstallLog
        # while (!($LogEntries.EndOfStream)) {
        #     $line = $LogEntries.ReadLine()
        #     if ($line -match 'Uninstall is') {Write-Host "$SystemStartMenuFolders`: $line"}
        # }
        # $LogEntries.Close()
        Remove-Item -Path $InstallPath -Recurse -Force | Out-Null
    }
    $StartMenu = Get-ChildItem -Path $SystemStartMenu -Filter $SystemStartMenuFolders*
    ForEach ($Folder in $StartMenu) {
        If (Test-Path -Path $Folder ) {
            Remove-Item -Path $Folder -Recurse -Force | Out-Null
        }
    }
}