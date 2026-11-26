@{
    RootModule           = 'OfficeC2R.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '318a9138-d622-44f1-9492-b7e22d51a600'
    Author               = 'powershell-utilities contributors'
    Description          = 'Office Click-to-Run queries: the update channel.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    RequiredModules      = @()
    FunctionsToExport    = @('Get-OfficeC2RChannel')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @('Get-Office365Channel')
}
