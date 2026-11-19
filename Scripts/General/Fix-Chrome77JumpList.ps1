<#
.SYNOPSIS
    Copies Chrome's jump list file so a pinned Chrome taskbar icon shows its jump list again.

.DESCRIPTION
    Looks in the current user's pinned taskbar folder
    ($env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\ImplicitAppShortcuts,
    including subfolders) for a shortcut whose name matches "Google Chrome". If one is found and the file
    version of its target (chrome.exe) has a major version above 76, the script copies
    $env:APPDATA\Microsoft\Windows\Recent\CustomDestinations\5d696d521de238c3.customDestinations-ms
    to a file in the same folder named after the pinned shortcut's parent folder, with
    the same .customDestinations-ms extension. Copy errors are suppressed. If no
    pinned Chrome shortcut is found, it writes a message to the host asking the user to
    unpin and repin Chrome. Produces no pipeline output.

.EXAMPLE
    .\Fix-Chrome77JumpList.ps1

    Restores the jump list for the current user's pinned Chrome icon, or prints the
    "Cannot locate the pinned icon" message.

.NOTES
    Run as the affected user (all paths are under that user's $env:APPDATA). No admin
    rights needed. Uses the WScript.Shell COM object, so Windows only. Written for the
    Chrome 77 jump list change. If the source .customDestinations-ms file does not
    exist, Get-Item writes an error.
#>
$CustomDestination = Get-Item -Path "$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations\5d696d521de238c3.customDestinations-ms"
$ChromePinned = Get-ChildItem -Recurse -Path "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\ImplicitAppShortcuts" | Where-Object { $_.Name -match "Google Chrome" }
If ($ChromePinned.Count -gt 0) {
    $sh = New-Object -ComObject WScript.Shell
    $details = $sh.CreateShortcut($ChromePinned.FullName)
    [Version]$Version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo("$($details.TargetPath)").FileVersion
    If ($Version.Major -gt '76') {
        Copy-Item $CustomDestination -Destination "$($CustomDestination.DirectoryName)\$($ChromePinned.Directory.Name)$($CustomDestination.Extension)" -ErrorAction SilentlyContinue
    }
}
Else {
    Write-Host "Cannot locate the pinned icon for Google Chrome.  Please manually unpin/repin the icon, then re-run this task."
}