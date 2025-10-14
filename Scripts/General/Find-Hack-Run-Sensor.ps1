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