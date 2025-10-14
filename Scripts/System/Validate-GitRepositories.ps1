#Requires -Version 5.1
<#
.SYNOPSIS
    PowerShell Git Repository Validation Script
    
.DESCRIPTION
    This script validates PowerShell Git repositories by:
    - Verifying Git repository initialization and configuration
    - Testing remote connectivity and access
    - Validating VSCode workspace files
    - Checking for uncommitted changes
    - Providing repository health summary
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$GitBaseDirectory = "D:\Dev\PowerShell-Projects",
    
    [Parameter()]
    [string]$WorkspaceDirectory = "D:\Dev\VSCode-Workspaces",
    
    [Parameter()]
    [string]$GiteaServerUrl = "https://git.example.com/"
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

function Test-GitRepositories {
    Write-Host "`n🔍 Validating Git Repositories" -ForegroundColor Cyan
    
    if (!(Test-Path $GitBaseDirectory)) {
        Write-StatusMessage "Git base directory not found: $GitBaseDirectory" "ERROR"
        return $false
    }
    
    $repositories = Get-ChildItem -Path $GitBaseDirectory -Directory
    $validationResults = @()
    
    foreach ($repo in $repositories) {
        Write-Host "`nTesting repository: $($repo.Name)" -ForegroundColor White
        
        $repoPath = $repo.FullName
        $result = [PSCustomObject]@{
            Name = $repo.Name
            Path = $repoPath
            HasGit = $false
            HasRemote = $false
            CanPull = $false
            FileCount = 0
            Status = "Unknown"
            Issues = @()
        }
        
        # Check if it's a Git repository
        if (Test-Path (Join-Path $repoPath ".git")) {
            $result.HasGit = $true
            Write-StatusMessage "Git repository initialized" "SUCCESS"
        } else {
            $result.Issues += "Not a Git repository"
            Write-StatusMessage "Not a Git repository" "ERROR"
        }
        
        # Check file count
        $result.FileCount = (Get-ChildItem $repoPath -Recurse -File | Measure-Object).Count
        Write-StatusMessage "Files: $($result.FileCount)"
        
        if ($result.HasGit) {
            Push-Location $repoPath
            try {
                # Check remote
                $remotes = git remote -v 2>$null
                if ($remotes) {
                    $result.HasRemote = $true
                    Write-StatusMessage "Remote configured" "SUCCESS"
                } else {
                    $result.Issues += "No remote configured"
                    Write-StatusMessage "No remote configured" "WARNING"
                }
                
                # Test connectivity to remote
                if ($result.HasRemote) {
                    try {
                        git ls-remote origin 2>$null | Out-Null
                        $result.CanPull = $true
                        Write-StatusMessage "Remote accessible" "SUCCESS"
                    } catch {
                        $result.Issues += "Cannot reach remote"
                        Write-StatusMessage "Cannot reach remote" "WARNING"
                    }
                }
                
                # Check Git status
                $status = git status --porcelain 2>$null
                if ($status) {
                    $result.Issues += "Uncommitted changes"
                    Write-StatusMessage "Uncommitted changes found" "WARNING"
                }
            }
            catch {
                $result.Issues += "Git command failed: $($_.Exception.Message)"
                Write-StatusMessage "Git command failed: $($_.Exception.Message)" "ERROR"
            }
            finally {
                Pop-Location
            }
        }
        
        # Determine overall status
        if ($result.HasGit -and $result.HasRemote -and $result.Issues.Count -eq 0) {
            $result.Status = "Healthy"
        } elseif ($result.HasGit -and $result.HasRemote) {
            $result.Status = "Warning"
        } else {
            $result.Status = "Error"
        }
        
        $validationResults += $result
    }
    
    return $validationResults
}

function Test-VSCodeWorkspaces {
    Write-Host "`n🔍 Validating VSCode Workspaces" -ForegroundColor Cyan
    
    if (!(Test-Path $WorkspaceDirectory)) {
        Write-StatusMessage "Workspace directory not found: $WorkspaceDirectory" "ERROR"
        return @()
    }
    
    $workspaces = Get-ChildItem -Path $WorkspaceDirectory -Filter "*.code-workspace"
    $workspaceResults = @()
    
    foreach ($workspace in $workspaces) {
        Write-Host "`nTesting workspace: $($workspace.Name)" -ForegroundColor White
        
        $result = [PSCustomObject]@{
            Name = $workspace.Name
            Path = $workspace.FullName
            Valid = $false
            FolderCount = 0
            MissingFolders = @()
            Issues = @()
        }
        
        try {
            $workspaceContent = Get-Content $workspace.FullName | ConvertFrom-Json
            
            if ($workspaceContent.folders) {
                $result.FolderCount = $workspaceContent.folders.Count
                Write-StatusMessage "Folders defined: $($result.FolderCount)"
                  foreach ($folder in $workspaceContent.folders) {
                    if ($folder.path -and (!(Test-Path $folder.path))) {
                        $result.MissingFolders += $folder.path
                    } elseif (!$folder.path) {
                        $result.MissingFolders += "(null path)"
                    }
                }
                
                if ($result.MissingFolders.Count -eq 0) {
                    $result.Valid = $true
                    Write-StatusMessage "All folders accessible" "SUCCESS"
                } else {
                    $result.Issues += "Missing folders: $($result.MissingFolders -join ', ')"
                    Write-StatusMessage "Missing folders: $($result.MissingFolders.Count)" "WARNING"
                }
            } else {
                $result.Issues += "No folders defined"
                Write-StatusMessage "No folders defined in workspace" "WARNING"
            }
        }
        catch {
            $result.Issues += "Failed to parse workspace file: $($_.Exception.Message)"
            Write-StatusMessage "Failed to parse workspace file" "ERROR"
        }
        
        $workspaceResults += $result
    }
    
    return $workspaceResults
}

function Set-GitConfiguration {
    Write-Host "`n⚙️  Configuring Git Settings" -ForegroundColor Cyan
    
    # Set global Git configuration if not already set
    try {
        $userName = git config --global user.name 2>$null
        $userEmail = git config --global user.email 2>$null
        
        if (!$userName) {
            $name = Read-Host "Enter your full name for Git commits"
            git config --global user.name $name
            Write-StatusMessage "Set Git user name: $name" "SUCCESS"
        } else {
            Write-StatusMessage "Git user name already set: $userName"
        }
        
        if (!$userEmail) {
            $email = Read-Host "Enter your email address for Git commits"
            git config --global user.email $email
            Write-StatusMessage "Set Git user email: $email" "SUCCESS"
        } else {
            Write-StatusMessage "Git user email already set: $userEmail"
        }
        
        # Set some useful Git defaults
        git config --global init.defaultBranch main
        git config --global push.default simple
        git config --global pull.rebase false
        
        Write-StatusMessage "Git configuration updated" "SUCCESS"
    }
    catch {
        Write-StatusMessage "Failed to configure Git: $($_.Exception.Message)" "ERROR"
    }
}

function Show-ValidationSummary {
    param(
        [Array]$RepoResults,
        [Array]$WorkspaceResults
    )
    
    Write-Host "`n📊 Validation Summary" -ForegroundColor Cyan
    
    # Repository summary
    $healthyRepos = $RepoResults | Where-Object Status -eq "Healthy"
    $warningRepos = $RepoResults | Where-Object Status -eq "Warning"
    $errorRepos = $RepoResults | Where-Object Status -eq "Error"
    
    Write-Host "`n📁 Repositories:" -ForegroundColor White
    Write-Host "  ✅ Healthy: $($healthyRepos.Count)" -ForegroundColor Green
    Write-Host "  ⚠️  Warning: $($warningRepos.Count)" -ForegroundColor Yellow
    Write-Host "  ❌ Error: $($errorRepos.Count)" -ForegroundColor Red
    
    if ($warningRepos.Count -gt 0) {
        Write-Host "`n⚠️  Repositories with warnings:" -ForegroundColor Yellow
        foreach ($repo in $warningRepos) {
            Write-Host "  - $($repo.Name): $($repo.Issues -join ', ')" -ForegroundColor White
        }
    }
    
    if ($errorRepos.Count -gt 0) {
        Write-Host "`n❌ Repositories with errors:" -ForegroundColor Red
        foreach ($repo in $errorRepos) {
            Write-Host "  - $($repo.Name): $($repo.Issues -join ', ')" -ForegroundColor White
        }
    }
    
    # Workspace summary
    $validWorkspaces = $WorkspaceResults | Where-Object Valid -eq $true
    $invalidWorkspaces = $WorkspaceResults | Where-Object Valid -eq $false
    
    Write-Host "`n🔧 VSCode Workspaces:" -ForegroundColor White
    Write-Host "  ✅ Valid: $($validWorkspaces.Count)" -ForegroundColor Green
    Write-Host "  ❌ Invalid: $($invalidWorkspaces.Count)" -ForegroundColor Red
    
    if ($invalidWorkspaces.Count -gt 0) {
        Write-Host "`n❌ Invalid workspaces:" -ForegroundColor Red
        foreach ($workspace in $invalidWorkspaces) {
            Write-Host "  - $($workspace.Name): $($workspace.Issues -join ', ')" -ForegroundColor White
        }
    }
}

function Show-NextSteps {
    param(
        [Array]$RepoResults
    )
      Write-Host "`n🎯 Next Steps" -ForegroundColor Cyan
    
    $healthyCount = ($RepoResults | Where-Object Status -eq "Healthy").Count
    $totalCount = $RepoResults.Count
    
    if ($healthyCount -eq $totalCount) {
        Write-Host "🎉 All repositories are healthy!" -ForegroundColor Green
        Write-Host "`nRecommended actions:" -ForegroundColor White
        Write-Host "1. Open VSCode workspaces from: $WorkspaceDirectory" -ForegroundColor White
        Write-Host "2. Test repositories by making sample commits" -ForegroundColor White
        Write-Host "3. Ensure your development workflow uses these locations" -ForegroundColor White
        Write-Host "4. Consider setting up automated backups for: $GitBaseDirectory" -ForegroundColor White
    } else {
        Write-Host "⚠️  Some repositories need attention:" -ForegroundColor Yellow
        Write-Host "1. Review and fix the repositories with errors or warnings" -ForegroundColor White
        Write-Host "2. Re-run this validation script after fixes" -ForegroundColor White
        Write-Host "3. Contact support if you need help with specific issues" -ForegroundColor White
    }
    
    Write-Host "`n🔗 Useful Git Commands:" -ForegroundColor Cyan
    Write-Host "Check repository status: git status" -ForegroundColor White
    Write-Host "Pull latest changes: git pull" -ForegroundColor White
    Write-Host "Add and commit changes: git add . && git commit -m 'Your message'" -ForegroundColor White
    Write-Host "Push changes: git push" -ForegroundColor White
}



# Main execution
function Start-RepositoryValidation {    Write-Host "🔍 PowerShell Git Repository Validation" -ForegroundColor Green
    Write-Host "=" * 45 -ForegroundColor Green
    
    # Configure Git if needed
    Set-GitConfiguration
    
    # Validate repositories
    $repoResults = Test-GitRepositories
    
    # Validate workspaces
    $workspaceResults = Test-VSCodeWorkspaces
    
    # Show summary
    Show-ValidationSummary -RepoResults $repoResults -WorkspaceResults $workspaceResults
    
    # Show next steps
    Show-NextSteps -RepoResults $repoResults
    
    Write-Host "`n✅ Repository validation complete!" -ForegroundColor Green
}

# Execute validation
Start-RepositoryValidation
