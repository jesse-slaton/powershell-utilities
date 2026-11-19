<#
.SYNOPSIS
    Exports enabled Windows workstation computer accounts and their OUs to a CSV file.

.DESCRIPTION
    Queries Active Directory with Get-ADComputer for enabled computer accounts whose
    OperatingSystem contains 'Windows' but not 'Windows Server', loading all properties
    (-Properties *). The filter also compares lastLogon with a date 45 days in the
    future ((Get-Date).AddDays(45)), so despite the $daysinactive variable it does not
    narrow the list to inactive computers.

    For each computer it writes a row with the columns Computer, Operating System, and
    OU (the distinguished name with its first component (the computer CN) removed) to OutputPath with
    Export-Csv, overwriting an existing file. On Windows PowerShell 5.1 the file starts
    with a #TYPE line because -NoTypeInformation is not used. Produces no console output.

.PARAMETER OutputPath
    Path of the CSV file to write. The folder must already exist. Defaults to
    workstationOUs.csv in the current user's Documents folder.

.EXAMPLE
    .\Get-AllWorkstationsOUs.ps1

    Writes the list to workstationOUs.csv in the current user's Documents folder.

.EXAMPLE
    .\Get-AllWorkstationsOUs.ps1 -OutputPath 'C:\Reports\workstationOUs.csv'

    Writes the list to C:\Reports\workstationOUs.csv.

.NOTES
    Requires the ActiveDirectory module (RSAT) and network access to a domain
    controller, run as a domain user with read access to computer objects. Loading every
    property for every workstation can be slow in a large domain.
#>
param(
    # CSV file to write. Defaults to workstationOUs.csv in the current user's Documents folder.
    [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'workstationOUs.csv')
)

$daysinactive = 45
$time = (get-date).AddDays($daysinactive)
$Workstations = Get-ADComputer -Filter { 
    OperatingSystem -notLike '*Windows Server*' 
    -and OperatingSystem -like '*Windows*' 
    -and Enabled -eq $true 
    -and lastLogon -lt $time} -Properties *
$ArrayofWorkstations = @()

ForEach ($Workstation in $Workstations) {
    $location = $Workstation.DistinguishedName -creplace "^[^,]*,", ""
    $ArrayofWorkstations += $Workstation | select-object `
        @{n = "Computer"; e = {$_.Name}}, `
        @{n = "Operating System"; e = {$_.OperatingSystem}}, `
        @{n = "OU"; e = {$location}}
}

$ArrayofWorkstations | Export-Csv $OutputPath