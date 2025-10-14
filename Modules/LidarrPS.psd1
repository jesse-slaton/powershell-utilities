@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'LidarrPS.psm1'
    
    # Version number of this module.
    ModuleVersion = '1.0.0'
    
    # ID used to uniquely identify this module
    GUID = '0e2e8b2c-3cc0-4eb4-a93b-6485adc6c14d'
    
    # Author of this module
    Author = 'Your Name'
    
    # Company or vendor of this module
    CompanyName = 'Your Company'
    
    # Copyright statement for this module
    Copyright = '(c) 2025. All rights reserved.'
    
    # Description of the functionality provided by this module
    Description = 'PowerShell module for interacting with the Lidarr API'
    
    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'
    
    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules = @()
    
    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = @(
        'Connect-Lidarr',
        'Get-LidarrArtist',
        'Get-LidarrAlbum',
        'Get-LidarrTrack',
        'Set-LidarrMonitoring',
        'Find-LidarrQualityAlbums'
    )
    
    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport = @()
    
    # Variables to export from this module
    VariablesToExport = '*'
    
    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport = @()
    
    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData = @{
        PSData = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('Lidarr', 'API', 'Music', 'MediaServer')
            
            # A URL to the license for this module.
            LicenseUri = ''
            
            # A URL to the main website for this project.
            ProjectUri = ''
            
            # A URL to an icon representing this module.
            # IconUri = ''
            
            # ReleaseNotes of this module
            ReleaseNotes = 'Initial release of the LidarrPS module.'
        }
    }
}