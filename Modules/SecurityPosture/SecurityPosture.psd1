@{
    RootModule           = 'SecurityPosture.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'f86ae008-3e61-4c6c-80b0-55a6d395e940'
    Author               = 'powershell-utilities contributors'
    Description          = 'Security posture checks: Device Guard security properties and status.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    RequiredModules      = @()
    FunctionsToExport    = @('Get-DeviceGuardSecurityProperty', 'Get-DeviceGuardStatus')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
}
