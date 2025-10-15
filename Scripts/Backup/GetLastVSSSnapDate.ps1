Invoke-Command -ScriptBlock {

    $LastSnap = Get-CimInstance -ClassName Win32_ShadowCopy -ErrorAction SilentlyContinue | Select-Object InstallDate | Sort-Object -Property InstallDate -Descending | Select-Object -First 1
    $Date = (Get-Date -f "ddd, dd MMM yyyy HH:mm zzz" $LastSnap.InstallDate) -replace '(.*)(\+|\-)([0-9][0-9]):([0-9][0-9])', '$1$2$3$4'
    Write-Output $Date
    
} -ComputerName .