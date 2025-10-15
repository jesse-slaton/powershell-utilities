@{
    RootModule = 'PackageManagerTUI.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'a8f3d2e1-6c4b-4a7f-9e5d-8b3c2a1f6e9d'
    Author = 'Jesse Slaton'
    CompanyName = ''
    Copyright = '(c) 2025 Jesse Slaton. All rights reserved.'
    Description = 'Terminal UI for managing winget packages and PowerShell modules. Provides search, install, update, and uninstall functionality with a text-based interface inspired by UniGetUI.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Start-PackageManagerTUI')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('TUI', 'PackageManager', 'winget', 'PSGallery', 'Terminal', 'UI')
            ProjectUri = 'https://github.com/jesse-slaton/powershell-utilities'
            ReleaseNotes = @'
v1.0.0 - Initial release
- Discover packages from winget and PowerShell Gallery
- Check for available updates
- Manage installed packages
- Search functionality
- Tab-based navigation
- Configurable settings
'@
        }
    }
}
