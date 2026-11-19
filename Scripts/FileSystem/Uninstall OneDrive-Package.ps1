<#
.SYNOPSIS
    Uninstalls OneDrive, deletes its folders, and hides it from the Explorer navigation pane.

.DESCRIPTION
    Writes progress messages and then:

    - maps an HKCR: drive to HKEY_CLASSES_ROOT (New-PSDrive, which also outputs the drive)
    - stops processes named OneDrive* and runs OneDriveSetup.exe /uninstall from
      $env:SYSTEMROOT\SysWOW64, or from System32 if it is not in SysWOW64, waiting for it
    - runs .\taskkill.exe /F /IM explorer.exe; this is a path relative to the current
      folder, so explorer is only stopped if taskkill.exe is in that folder
    - deletes $env:USERPROFILE\OneDrive (including any files still in it),
      $env:LOCALAPPDATA\Microsoft\OneDrive, $env:PROGRAMDATA\Microsoft OneDrive and
      $env:SYSTEMDRIVE\OneDriveTemp
    - creates if needed the CLSID {018D5C66-4533-4307-9B53-224DE2ED1FE6} keys (native
      and Wow6432Node) under HKCR and sets System.IsPinnedToNameSpaceTree to 0
    - starts explorer.exe

    Errors (for example no OneDrive process running, or a folder already gone) are
    written but do not stop the script. Changes system state and deletes user data.

.EXAMPLE
    .\Uninstall OneDrive-Package.ps1

    Removes OneDrive for the current user and computer.

.NOTES
    Requires administrator rights (HKEY_CLASSES_ROOT and ProgramData changes). The
    per-user folders removed are those of the account that runs the script; when run as
    Local System by a deployment tool, that is not the logged-on user's profile.
#>
Write-Output "Uninstalling OneDrive. Please wait."
    
    New-PSDrive  HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT
    $onedrive = "$env:SYSTEMROOT\SysWOW64\OneDriveSetup.exe"
    $ExplorerReg1 = "HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"
    $ExplorerReg2 = "HKCR:\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"
	Stop-Process -Name "OneDrive*"
	Start-Sleep 2
	If (!(Test-Path $onedrive)) {
		$onedrive = "$env:SYSTEMROOT\System32\OneDriveSetup.exe"
	}
	Start-Process $onedrive "/uninstall" -NoNewWindow -Wait
	Start-Sleep 2
    Write-Output "Stopping explorer"
    Start-Sleep 1
	.\taskkill.exe /F /IM explorer.exe
	Start-Sleep 3
    Write-Output "Removing leftover files"
	Remove-Item "$env:USERPROFILE\OneDrive" -Force -Recurse
	Remove-Item "$env:LOCALAPPDATA\Microsoft\OneDrive" -Force -Recurse
	Remove-Item "$env:PROGRAMDATA\Microsoft OneDrive" -Force -Recurse
	If (Test-Path "$env:SYSTEMDRIVE\OneDriveTemp") {
		Remove-Item "$env:SYSTEMDRIVE\OneDriveTemp" -Force -Recurse
	}
    Write-Output "Removing OneDrive from windows explorer"
    If (!(Test-Path $ExplorerReg1)) {
        New-Item $ExplorerReg1
    }
    Set-ItemProperty $ExplorerReg1 System.IsPinnedToNameSpaceTree -Value 0 
    If (!(Test-Path $ExplorerReg2)) {
        New-Item $ExplorerReg2
    }
    Set-ItemProperty $ExplorerReg2 System.IsPinnedToNameSpaceTree -Value 0
    Write-Output "Restarting Explorer that was shut down before."
    Start explorer.exe -NoNewWindow
