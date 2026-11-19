<#
.SYNOPSIS
    Exports an HTML report for every Group Policy Object in the domain.

.DESCRIPTION
    Gets every GPO with Get-GPO -All and writes Get-GPOReport -ReportType HTML for each to
    C:\GPOExport\<GPO display name>.html. Produces no pipeline output.

.EXAMPLE
    .\GPOAudit.ps1

    Writes one HTML report per GPO to C:\GPOExport.

.NOTES
    Requires the GroupPolicy module (RSAT Group Policy Management Tools), a domain-joined
    computer, and read access to the domain's GPOs. The C:\GPOExport folder must exist.
    GPO names containing characters that are invalid in file names make that report fail.
#>
$GPOs = Get-GPO -all
foreach ($gpo in $GPOs) {
    Get-GPOReport -Guid $gpo.id -ReportType HTML -Path "C:\GPOExport\$($gpo.displayName).html"
}
#% { Get-GPOReport -GUID $.id -ReportType HTML -Path "C:\GPOExport\$($gpo.displayName).html" }