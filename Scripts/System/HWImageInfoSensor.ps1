<#
.SYNOPSIS
    Reports imaging details stored under HKLM:\System\Contoso as one pipe-delimited line.

.DESCRIPTION
    Reads the values 'Date Imaged', 'Image Info', 'TaskSequence ID', 'Tasksequencename'
    and 'Tasksequencename2nd' from HKLM:\System\Contoso (a key written at imaging time)
    and writes them with Write-Host in the form:

        <DateImaged>|<ImageInfo>|<TaskSequenceID>|<TaskSequenceName>|<TaskSequenceName2nd>

    The line ends with a trailing space. 'Date Imaged' is parsed with Get-Date, so its
    rendered form depends on the current culture. If the key does not exist the script
    writes "Contoso registry key not found". Read-only.

    Output goes through Write-Host (the information stream), not the success pipeline.

.EXAMPLE
    .\HWImageInfoSensor.ps1

    <DateImaged>|<ImageInfo>|<TaskSequenceID>|<TaskSequenceName>|<TaskSequenceName2nd>

.NOTES
    None. Reading HKLM does not need admin rights. The registry key name (Contoso) is a
    placeholder for the organization-specific key written by the imaging process; the
    script is shaped as an endpoint-management sensor (single delimited line).
#>
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
