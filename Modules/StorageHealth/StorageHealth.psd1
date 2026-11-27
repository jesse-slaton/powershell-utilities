@{
    RootModule           = 'StorageHealth.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'a17bd6cc-20ad-414b-82ed-2b479e9152c1'
    Author               = 'powershell-utilities contributors'
    Description          = 'Disk, SMART, SSD and Volume Shadow Copy checks for the local computer.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    RequiredModules      = @()
    FunctionsToExport    = @('Enable-SystemDriveRestore', 'Get-DriveHealth', 'Get-LastShadowCopyDate', 'Get-ShadowStorageMaxSize',
        'Get-SmartAttribute', 'Test-ShadowCopy')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
}
