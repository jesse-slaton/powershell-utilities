$LUAKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
$EnableLUA = Get-ItemProperty -Path $LUAKey -Name EnableLUA
If (1 -eq $EnableLUA.EnableLUA) {
    
}