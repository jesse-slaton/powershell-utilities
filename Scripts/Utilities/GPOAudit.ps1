$GPOs = Get-GPO -all
foreach ($gpo in $GPOs) {
    Get-GPOReport -Guid $gpo.id -ReportType HTML -Path "C:\GPOExport\$($gpo.displayName).html"
}
#% { Get-GPOReport -GUID $.id -ReportType HTML -Path "C:\GPOExport\$($gpo.displayName).html" }