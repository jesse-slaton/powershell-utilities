@{
    RootModule           = 'MsiTools.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '954d2b9e-2a90-4957-b3b3-24d0559748a2'
    Author               = 'powershell-utilities contributors'
    Description          = 'Windows Installer helpers: color an MSI log on the console and read the properties of an MSI file.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    RequiredModules      = @()
    FunctionsToExport    = @('Format-MsiLog', 'Get-MsiFileInfo')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @('Colorize-MsiLog', 'Get-MSIProperties')
}
