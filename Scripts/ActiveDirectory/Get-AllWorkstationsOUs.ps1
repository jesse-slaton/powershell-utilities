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