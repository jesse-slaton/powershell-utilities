$ContosoKey = "HKLM:\System\Contoso"
If (Test-Path $ContosoKey) {
    $ContosoHive = Get-ItemProperty $ContosoKey
    If ($null -ne $ContosoHive) {
        [DateTime]$DateImaged = If ($null -ne $ContosoHive.'Date Imaged') { Get-Date -Date $ContosoHive.'Date Imaged' }
        [String]$ImageInfo = $ContosoHive.'Image Info'
        [String]$TSID = $ContosoHive.'TaskSequence ID'
        [String]$TSName = $ContosoHive.'Tasksequencename'
        [String]$TSName2nd = $ContosoHive.'Tasksequencename2nd'
        Write-Host "$DateImaged|$ImageInfo|$TSID|$TSName|$TSName2nd "
    }
    Else {
        Write-Host "No registry values found in Contoso registry key" -ErrorAction Stop
    }
}
Else {
    Write-Host "Contoso registry key not found" -ErrorAction Stop
}
