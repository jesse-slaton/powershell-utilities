<#
.SYNOPSIS
    Sensor that lists hack-run*.png files in every user's Internet Explorer cache, with size and MD5 hash.

.DESCRIPTION
    Searches C:\Users\*\AppData\Local\Microsoft\Windows\INetCache\IE\*\ recursively
    (including hidden files, errors suppressed) for files named hack-run*.png. For each
    file it writes one line:

        <Folder>|<FileName>|<CreationTime>|<Size>|<MD5>

    where Size is a friendly value such as "12.34 KB". If no file is found it writes
    "File not found." with Write-Host. Read-only.

.EXAMPLE
    .\Find-Hack-Run-Sensor.ps1

    Lists matching cache files for all user profiles, or "File not found.".

.NOTES
    Named as a sensor, but takes no sensor parameters and runs on its own. Needs administrator or SYSTEM rights to read other users'
    profiles. The profile root C:\Users is hard-coded. Requires PowerShell 4.0 or
    later (Get-FileHash).
#>
$IEHackFiles = Get-ChildItem "C:\Users\*\AppData\Local\Microsoft\Windows\INetCache\IE\*\hack-run*.png" -Recurse -Force -ErrorAction SilentlyContinue
#$IEHackFiles = Get-ChildItem "C:\Users\*\AppData\Local\Microsoft\Windows\INetCache\IE\*\WebResource*.js" -Recurse -Force -ErrorAction SilentlyContinue
function Get-FriendlySize {
    param($Bytes)
    $sizes='Bytes,KB,MB,GB,TB,PB,EB,ZB' -split ','
    for($i=0; ($Bytes -ge 1kb) -and 
        ($i -lt $sizes.Count); $i++) {$Bytes/=1kb}
    $N=2; if($i -eq 0) {$N=0}
    "{0:N$($N)} {1}" -f $Bytes, $sizes[$i]
}

If ($IEHackFiles) {
ForEach ($File in $IEHackFiles) {
    $hash = (Get-FileHash -Path $file.FullName -Algorithm MD5).Hash
    $file.Directory.ToString() + "|" + $file.Name.ToString() + "|" + $file.CreationTime.ToString() + "|" + $(Get-FriendlySize -Bytes $file.Length) + "|" + $Hash
    }
}
Else {
    Write-Host "File not found."
}