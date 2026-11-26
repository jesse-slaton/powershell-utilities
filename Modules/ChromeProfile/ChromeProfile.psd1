@{
    RootModule           = 'ChromeProfile.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'a0efb577-b8d8-473e-b7b6-a6d5045fbf44'
    Author               = 'powershell-utilities contributors'
    Description          = 'Google Chrome profile helpers: back up and restore a profile or its bookmarks, and list the installed extensions.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    RequiredModules      = @()
    FunctionsToExport    = @('Backup-ChromeBookmark', 'Backup-ChromeProfile', 'Get-ChromeExtension', 'Restore-ChromeBookmark', 'Restore-ChromeProfile')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @('Backup-ChromeBookmarks', 'Restore-ChromeBookmarks')
}
