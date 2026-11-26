@{
    RootModule           = 'PathRepair.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '16faef46-e331-47f2-9165-10cdc1de76f1'
    Author               = 'powershell-utilities contributors'
    Description          = 'PATH environment variable helpers: report malformed PATH entries and restore the User PATH from its BADPATH backup.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    RequiredModules      = @()
    FunctionsToExport    = @('Get-MalformedPathEntry', 'Restore-PathFromBackup')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @('Get-MalformedPathEntries')
}
