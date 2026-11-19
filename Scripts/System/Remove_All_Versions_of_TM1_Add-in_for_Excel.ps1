<#
.SYNOPSIS
    Uninstalls IBM Planning Analytics for Microsoft Office (TM1 add-in for Excel) and removes its leftovers.

.DESCRIPTION
    Loops over two install folders,
    C:\Program Files\ibm\cognos\IBM for Microsoft Office and its Program Files (x86)
    counterpart. For each folder that exists, it runs
    <folder>\uninstall\uninst.exe with the arguments -u -s (started with
    Start-Process -WindowStyle Hidden -Wait), then deletes the install folder
    (-Recurse -Force). On every pass of the loop, whether or not that folder exists, it
    also deletes any folder under C:\ProgramData\Microsoft\Windows\Start Menu\Programs
    whose name starts with "IBM Planning Analytics for Microsoft Office". Produces no
    output.

    The script also opens $env:TEMP\cognos_uninst_log.txt to test whether it is locked,
    but ignores the result. The paths and uninstaller arguments are variables at the top
    of the script.

.EXAMPLE
    .\Remove_All_Versions_of_TM1_Add-in_for_Excel.ps1

    Silently removes all installed copies of the add-in.

.NOTES
    Requires administrator rights (Program Files and the all-users Start Menu). Close
    Excel first so the add-in files are not in use.
#>

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