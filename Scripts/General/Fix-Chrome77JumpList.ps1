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