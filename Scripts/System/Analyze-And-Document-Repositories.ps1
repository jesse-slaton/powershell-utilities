#Requires -Version 5.1
<#
.SYNOPSIS
    Analyzes PowerShell repositories and generates/updates comprehensive README.md files
    
.DESCRIPTION
    This script analyzes each repository to:
    - Examine all scripts and extract functionality information
    - Verify existing README.md files for accuracy and completeness
    - Generate enhanced documentation with proper structure
    - Commit changes to Git repositories
    - Update repository descriptions on Gitea
    
.PARAMETER GitBaseDirectory
    The base directory containing Git repositories (default: D:\Dev\PowerShell-Projects)
    
.PARAMETER GiteaServerUrl
    The Gitea server URL (default: https://git.example.com/)
    
.PARAMETER WhatIf
    Shows what would be done without making changes
    
.PARAMETER SkipGitCommit
    Analyze and update files but don't commit to Git
    
.PARAMETER Force
    Overwrite existing README files even if they appear complete
    
.EXAMPLE
    .\Analyze-And-Document-Repositories.ps1 -WhatIf
    
.EXAMPLE
    .\Analyze-And-Document-Repositories.ps1 -Force
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$GitBaseDirectory = "D:\Dev\PowerShell-Projects",
    
    [Parameter()]
    [string]$GiteaServerUrl = "https://git.example.com/",
    
    [Parameter()]
    [switch]$WhatIf,
    
    [Parameter()]
    [switch]$SkipGitCommit,
    
    [Parameter()]
    [switch]$Force
)

function Write-StatusMessage {
    param([string]$Message, [string]$Status = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    switch ($Status) {
        "SUCCESS" { Write-Host "[$timestamp] ✅ $Message" -ForegroundColor Green }
        "WARNING" { Write-Host "[$timestamp] ⚠️  $Message" -ForegroundColor Yellow }
        "ERROR"   { Write-Host "[$timestamp] ❌ $Message" -ForegroundColor Red }
        default   { Write-Host "[$timestamp] ℹ️  $Message" -ForegroundColor Cyan }
    }
}

function Get-ScriptSynopsis {
    param([string]$FilePath)
    
    try {
        $content = Get-Content $FilePath -Raw
        
        # Extract synopsis from comment-based help
        if ($content -match '\.SYNOPSIS\s*\n(.*?)(?=\n\s*\.|\n\s*#>|\Z)') {
            $synopsis = $matches[1].Trim()
            return $synopsis -replace '\s+', ' '
        }
        
        # Look for descriptive comments at the top
        $lines = Get-Content $FilePath
        foreach ($line in $lines[0..10]) {
            if ($line -match '^#\s*(.+)' -and $line -notmatch '^#!') {
                $comment = $matches[1].Trim()
                if ($comment.Length -gt 10 -and $comment -notmatch '^(Author|Created|Modified|Version)') {
                    return $comment
                }
            }
        }
        
        # Try to infer from filename
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
        return "PowerShell script: $baseName"
    }
    catch {
        return "PowerShell script"
    }
}

function Get-ScriptParameters {
    param([string]$FilePath)
    
    try {
        $content = Get-Content $FilePath -Raw
        $parameters = @()
        
        # Look for param blocks
        if ($content -match '(?s)param\s*\((.*?)\)') {
            $paramBlock = $matches[1]
            
            # Extract individual parameters
            $paramMatches = [regex]::Matches($paramBlock, '\[Parameter[^\]]*\]\s*\[([^\]]+)\]\s*\$(\w+)')
            foreach ($match in $paramMatches) {
                $parameters += @{
                    Name = $match.Groups[2].Value
                    Type = $match.Groups[1].Value
                }
            }
        }
        
        return $parameters
    }
    catch {
        return @()
    }
}

function Analyze-Repository {
    param([string]$RepositoryPath)
    
    $repoName = Split-Path $RepositoryPath -Leaf
    Write-StatusMessage "Analyzing repository: $repoName"
    
    $analysis = [PSCustomObject]@{
        Name = $repoName
        Path = $RepositoryPath
        ScriptFiles = @()
        ConfigFiles = @()
        DocumentationFiles = @()
        OtherFiles = @()
        HasExistingReadme = $false
        ExistingReadmeQuality = "Unknown"
        SuggestedDescription = ""
        MainPurpose = ""
        KeyFeatures = @()
        RequiredModules = @()
        FileCount = 0
    }
    
    # Get all files
    $allFiles = Get-ChildItem $RepositoryPath -Recurse -File | Where-Object { $_.Name -notlike ".*" }
    $analysis.FileCount = $allFiles.Count
    
    # Categorize files
    foreach ($file in $allFiles) {
        $extension = $file.Extension.ToLower()
        switch ($extension) {
            {$_ -in '.ps1', '.psm1', '.psd1'} {
                $scriptInfo = @{
                    Name = $file.Name
                    Path = $file.FullName
                    RelativePath = $file.FullName.Replace("$RepositoryPath\", "")
                    Type = switch ($extension) {
                        '.ps1' { 'Script' }
                        '.psm1' { 'Module' }
                        '.psd1' { 'Manifest' }
                    }
                    Synopsis = Get-ScriptSynopsis $file.FullName
                    Parameters = Get-ScriptParameters $file.FullName
                    Size = $file.Length
                }
                $analysis.ScriptFiles += $scriptInfo
            }
            {$_ -in '.vbs', '.bat', '.cmd'} {
                $analysis.ScriptFiles += @{
                    Name = $file.Name
                    Path = $file.FullName
                    RelativePath = $file.FullName.Replace("$RepositoryPath\", "")
                    Type = 'Legacy Script'
                    Synopsis = "Legacy script: $($file.BaseName)"
                    Parameters = @()
                    Size = $file.Length
                }
            }
            {$_ -in '.xml', '.json', '.yaml', '.yml', '.config', '.ini', '.cfg'} {
                $analysis.ConfigFiles += $file
            }
            {$_ -in '.md', '.txt', '.doc', '.docx', '.pdf'} {
                $analysis.DocumentationFiles += $file
                if ($file.Name -eq "README.md") {
                    $analysis.HasExistingReadme = $true
                }
            }
            default {
                $analysis.OtherFiles += $file
            }
        }
    }
    
    # Analyze existing README if present
    if ($analysis.HasExistingReadme) {
        $readmePath = Join-Path $RepositoryPath "README.md"
        $readmeContent = Get-Content $readmePath -Raw
        
        # Simple quality assessment
        $hasDescription = $readmeContent -match '(?i)description|overview|about'
        $hasUsage = $readmeContent -match '(?i)usage|example|how to'
        $hasRequirements = $readmeContent -match '(?i)requirement|prerequisite|depend'
        $wordCount = ($readmeContent -split '\s+').Count
        
        if ($wordCount -lt 50) {
            $analysis.ExistingReadmeQuality = "Minimal"
        } elseif ($hasDescription -and $hasUsage -and $wordCount -gt 100) {
            $analysis.ExistingReadmeQuality = "Good"
        } elseif ($hasDescription -or $hasUsage) {
            $analysis.ExistingReadmeQuality = "Basic"
        } else {
            $analysis.ExistingReadmeQuality = "Poor"
        }
    }
    
    # Infer main purpose from repository name and contents
    $analysis.MainPurpose = Get-RepositoryPurpose $repoName $analysis.ScriptFiles
    $analysis.SuggestedDescription = Get-RepositoryDescription $repoName $analysis.ScriptFiles
    $analysis.KeyFeatures = Get-KeyFeatures $analysis.ScriptFiles
    
    return $analysis
}

function Get-RepositoryPurpose {
    param([string]$RepoName, [array]$ScriptFiles)
    
    $repoName = $RepoName.ToLower()
    
    # Repository-specific purposes
    $purposes = @{
        'activedirectory' = 'Active Directory administration and user management'
        'application' = 'Application deployment, configuration, and management'
        'backup' = 'Backup and recovery operations'
        'network' = 'Network infrastructure management and monitoring'
        'security' = 'Security compliance and monitoring tools'
        'system' = 'System maintenance and administration'
        'office' = 'Microsoft Office deployment and configuration'
        'monitoring' = 'System monitoring and reporting'
        'utilities' = 'General utility scripts and tools'
        'deployment' = 'Software deployment and configuration'
        'legacy' = 'Legacy scripts and compatibility tools'
        'individual' = 'Collection of standalone utility scripts'
    }
    
    foreach ($key in $purposes.Keys) {
        if ($repoName -like "*$key*") {
            return $purposes[$key]
        }
    }
    
    # Analyze script content for clues
    $scriptSynopses = $ScriptFiles | ForEach-Object { $_.Synopsis.ToLower() }
    $combinedText = $scriptSynopses -join ' '
    
    if ($combinedText -match 'active directory|ad |user|group') {
        return 'Active Directory and user management tools'
    } elseif ($combinedText -match 'backup|restore|recovery') {
        return 'Backup and recovery utilities'
    } elseif ($combinedText -match 'network|ip|dns|dhcp') {
        return 'Network administration tools'
    } elseif ($combinedText -match 'monitor|report|log|health') {
        return 'Monitoring and reporting tools'
    } elseif ($combinedText -match 'install|deploy|config') {
        return 'Deployment and configuration scripts'
    } else {
        return 'PowerShell automation scripts'
    }
}

function Get-RepositoryDescription {
    param([string]$RepoName, [array]$ScriptFiles)
    
    $purpose = Get-RepositoryPurpose $RepoName $ScriptFiles
    $scriptCount = $ScriptFiles.Count
    
    return "This repository contains $scriptCount PowerShell scripts for $purpose."
}

function Get-KeyFeatures {
    param([array]$ScriptFiles)
    
    $features = @()
    
    # Analyze script names and synopses for common patterns
    $scriptTexts = $ScriptFiles | ForEach-Object { "$($_.Name) $($_.Synopsis)".ToLower() }
    $combinedText = $scriptTexts -join ' '
    
    # Common feature patterns
    $featurePatterns = @{
        'User management' = 'user|account|password|profile'
        'Group management' = 'group|member|permission|acl'
        'System monitoring' = 'monitor|health|status|check|performance'
        'Report generation' = 'report|export|csv|html|output'
        'Configuration management' = 'config|setting|registry|policy'
        'Backup operations' = 'backup|restore|copy|archive'
        'Network operations' = 'network|ip|dns|ping|connection'
        'Security auditing' = 'security|audit|compliance|scan'
        'Application deployment' = 'install|deploy|uninstall|package'
        'Log analysis' = 'log|event|parse|analyze'
        'Database operations' = 'database|sql|query|table'
        'File operations' = 'file|folder|directory|path'
        'Service management' = 'service|process|daemon|start|stop'
        'Remote operations' = 'remote|invoke|session|computer'
        'Scheduled tasks' = 'schedule|task|job|cron'
    }
    
    foreach ($feature in $featurePatterns.Keys) {
        $pattern = $featurePatterns[$feature]
        if ($combinedText -match $pattern) {
            $features += $feature
        }
    }
    
    return $features | Select-Object -First 5  # Limit to top 5 features
}

function Generate-ReadmeContent {
    param([PSCustomObject]$Analysis)
    
    $repoName = $Analysis.Name
    $displayName = $repoName -replace '-', ' ' -replace '_', ' '
    
    $readme = @"
# $displayName

$($Analysis.SuggestedDescription)

## 📋 Overview

$($Analysis.MainPurpose)

This repository contains **$($Analysis.ScriptFiles.Count) scripts** across $($Analysis.FileCount) total files.

"@

    # Add key features if any
    if ($Analysis.KeyFeatures.Count -gt 0) {
        $readme += @"

## ✨ Key Features

"@
        foreach ($feature in $Analysis.KeyFeatures) {
            $readme += "- $feature`n"
        }
        $readme += "`n"
    }

    # Add scripts documentation
    if ($Analysis.ScriptFiles.Count -gt 0) {
        $readme += @"
## 📝 Scripts

"@
        
        # Group scripts by type
        $scriptsByType = $Analysis.ScriptFiles | Group-Object Type
        
        foreach ($typeGroup in $scriptsByType) {
            if ($typeGroup.Count -gt 1) {
                $readme += "`n### $($typeGroup.Name)s`n`n"
            }
            
            foreach ($script in $typeGroup.Group | Sort-Object Name) {
                $readme += "### ``$($script.Name)```n`n"
                $readme += "$($script.Synopsis)`n`n"
                
                if ($script.Parameters.Count -gt 0) {
                    $readme += "**Parameters:**`n"
                    foreach ($param in $script.Parameters) {
                        $readme += "- ``$($param.Name)`` [$($param.Type)] `n"
                    }
                    $readme += "`n"
                }
                
                $readme += "**Location:** ``$($script.RelativePath)```n`n"
            }
        }
    }

    # Add configuration files section if any
    if ($Analysis.ConfigFiles.Count -gt 0) {
        $readme += @"
## ⚙️ Configuration Files

"@
        foreach ($configFile in $Analysis.ConfigFiles | Sort-Object Name) {
            $readme += "- ``$($configFile.Name)`` - Configuration file`n"
        }
        $readme += "`n"
    }

    # Add requirements section
    $readme += @"
## 📋 Requirements

- PowerShell 5.1 or later
- Appropriate permissions for the operations performed by these scripts

"@

    # Add requirements based on script analysis
    $allScriptContent = ($Analysis.ScriptFiles | ForEach-Object { 
        try { Get-Content $_.Path -Raw } catch { "" } 
    }) -join "`n"
    
    if ($allScriptContent -match 'Import-Module|Get-Module') {
        $readme += "- Required PowerShell modules (install as needed)`n"
    }
    if ($allScriptContent -match 'ActiveDirectory|Get-ADUser|Get-ADGroup') {
        $readme += "- Active Directory PowerShell module`n"
    }
    if ($allScriptContent -match 'Exchange|Get-Mailbox') {
        $readme += "- Exchange Management Tools`n"
    }
    if ($allScriptContent -match 'VMware|Get-VM') {
        $readme += "- VMware PowerCLI`n"
    }

    $readme += @"

## 🚀 Usage

1. **Clone or download** this repository
2. **Review each script** before running to understand its functionality
3. **Modify parameters** as needed for your environment
4. **Run with appropriate permissions** for your target systems

### Example Usage

``````powershell
# Navigate to the script directory
cd "$repoName"

# Run a script (example)
.\ScriptName.ps1 -Parameter Value
``````

## ⚠️ Important Notes

- **Always test scripts** in a non-production environment first
- **Review and modify** scripts to match your specific requirements
- **Ensure you have proper permissions** before running administrative scripts
- **Back up important data** before running modification scripts

## 📁 Repository Structure

``````
$repoName/
"@

    # Generate file tree
    $allItems = Get-ChildItem $Analysis.Path -Recurse | Where-Object { $_.Name -notlike ".*" }
    $directories = $allItems | Where-Object { $_.PSIsContainer } | Sort-Object FullName
    $files = $allItems | Where-Object { -not $_.PSIsContainer } | Sort-Object FullName
    
    # Add directories first
    foreach ($dir in $directories) {
        $relativePath = $dir.FullName.Replace("$($Analysis.Path)\", "").Replace('\', '/')
        $level = ($relativePath.Split('/')).Count - 1
        $indent = "  " * $level
        $readme += "$indent├── $($dir.Name)/`n"
    }
    
    # Add files (limit to key files to avoid clutter)
    $keyFiles = $files | Where-Object { 
        $_.Extension -in '.ps1', '.psm1', '.psd1', '.md', '.txt', '.json', '.xml' -or
        $_.Name -in 'README.md', 'LICENSE', '.gitignore'
    } | Select-Object -First 20
    
    foreach ($file in $keyFiles) {
        $relativePath = $file.FullName.Replace("$($Analysis.Path)\", "").Replace('\', '/')
        $level = ($relativePath.Split('/')).Count - 1
        $indent = "  " * $level
        $readme += "$indent├── $($file.Name)`n"
    }
    
    if ($files.Count -gt 20) {
        $readme += "  └── ... and $($files.Count - 20) more files`n"
    }

    $readme += @"
``````

## 🤝 Contributing

Feel free to submit issues, fork the repository, and create pull requests for any improvements.

## 📄 License

This project is provided as-is for educational and administrative purposes.

---

**Generated on:** $(Get-Date -Format "yyyy-MM-dd")  
**Total Scripts:** $($Analysis.ScriptFiles.Count)  
**Repository Size:** $([math]::Round(($allItems | Measure-Object Length -Sum).Sum / 1MB, 2)) MB
"@

    return $readme
}

function Update-Repository {
    param([PSCustomObject]$Analysis, [switch]$Force)
    
    $readmePath = Join-Path $Analysis.Path "README.md"
    $shouldUpdate = $Force -or 
                   -not $Analysis.HasExistingReadme -or 
                   $Analysis.ExistingReadmeQuality -in @("Minimal", "Poor")
    
    if (-not $shouldUpdate) {
        Write-StatusMessage "README.md exists and appears adequate ($($Analysis.ExistingReadmeQuality)). Use -Force to overwrite." "INFO"
        return $false
    }
    
    if ($WhatIf) {
        Write-StatusMessage "WHATIF: Would update README.md in $($Analysis.Name)"
        return $true
    }
    
    try {
        $newContent = Generate-ReadmeContent $Analysis
        Set-Content -Path $readmePath -Value $newContent -Encoding UTF8
        Write-StatusMessage "Updated README.md for $($Analysis.Name)" "SUCCESS"
        return $true
    }
    catch {
        Write-StatusMessage "Failed to update README.md for $($Analysis.Name): $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Commit-Changes {
    param([string]$RepositoryPath, [string]$CommitMessage = "Update README.md with enhanced documentation")
    
    if ($WhatIf -or $SkipGitCommit) {
        Write-StatusMessage "WHATIF: Would commit changes to Git"
        return
    }
    
    Push-Location $RepositoryPath
    try {
        $status = git status --porcelain 2>$null
        if ($status) {
            git add README.md 2>$null
            git commit -m $CommitMessage 2>$null
            
            if ($LASTEXITCODE -eq 0) {
                Write-StatusMessage "Committed changes to Git" "SUCCESS"
                
                # Push to remote
                git push 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-StatusMessage "Pushed changes to remote repository" "SUCCESS"
                } else {
                    Write-StatusMessage "Failed to push to remote repository" "WARNING"
                }
            } else {
                Write-StatusMessage "Failed to commit changes" "ERROR"
            }
        } else {
            Write-StatusMessage "No changes to commit" "INFO"
        }
    }
    catch {
        Write-StatusMessage "Git operation failed: $($_.Exception.Message)" "ERROR"
    }
    finally {
        Pop-Location
    }
}

# Main execution
function Start-RepositoryAnalysis {
    Write-Host "🔍 PowerShell Repository Analysis & Documentation" -ForegroundColor Green
    Write-Host "=" * 60 -ForegroundColor Green
    
    if (!(Test-Path $GitBaseDirectory)) {
        Write-StatusMessage "Base directory not found: $GitBaseDirectory" "ERROR"
        return
    }
    
    $repositories = Get-ChildItem $GitBaseDirectory -Directory | 
                   Where-Object { Test-Path (Join-Path $_.FullName ".git") }
    
    Write-StatusMessage "Found $($repositories.Count) Git repositories to analyze"
    
    $results = @()
    
    foreach ($repo in $repositories) {
        Write-Host "`n" + "="*50 -ForegroundColor Cyan
        
        try {
            $analysis = Analyze-Repository $repo.FullName
            $updated = Update-Repository $analysis -Force:$Force
            
            if ($updated -and -not $WhatIf) {
                Commit-Changes $repo.FullName
            }
            
            $results += [PSCustomObject]@{
                Repository = $repo.Name
                Scripts = $analysis.ScriptFiles.Count
                TotalFiles = $analysis.FileCount
                ReadmeQuality = $analysis.ExistingReadmeQuality
                Updated = $updated
                MainPurpose = $analysis.MainPurpose
            }
        }
        catch {
            Write-StatusMessage "Failed to analyze $($repo.Name): $($_.Exception.Message)" "ERROR"
        }
    }
    
    # Summary report
    Write-Host "`n" + "="*60 -ForegroundColor Green
    Write-Host "📊 Analysis Summary" -ForegroundColor Green
    Write-Host "="*60 -ForegroundColor Green
    
    $totalScripts = ($results | Measure-Object Scripts -Sum).Sum
    $updatedCount = ($results | Where-Object Updated).Count
    
    Write-Host "Repositories analyzed: $($results.Count)" -ForegroundColor Cyan
    Write-Host "Total scripts documented: $totalScripts" -ForegroundColor Cyan
    Write-Host "README files updated: $updatedCount" -ForegroundColor Cyan
    
    # Show results table
    $results | Sort-Object Repository | Format-Table -AutoSize
    
    Write-Host "`n✅ Repository analysis complete!" -ForegroundColor Green
    
    if (-not $WhatIf -and -not $SkipGitCommit) {
        Write-Host "`n🔗 Your repositories are now documented and pushed to Gitea!" -ForegroundColor Green
        Write-Host "View them at: $GiteaServerUrl" -ForegroundColor Cyan
    }
}

# Execute analysis
Start-RepositoryAnalysis
