Invoke-Command -ScriptBlock {

    $HasSnap = Get-CimInstance -ClassName Win32_ShadowCopy -ErrorAction SilentlyContinue
    $Output = $HasSnap.Count -gt 0
    Write-Output $Output
    
} -ComputerName .