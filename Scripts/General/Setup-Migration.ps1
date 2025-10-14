# NOTE: Requires external repo at D:\dev\repos\Windows-Secure-Host-Baseline
# Original repo: https://git.example.com/sydlexius/Windows-Secure-Host-Baseline.git

# NOTE: Requires external repo at D:\dev\repos\PowerShell-Individual-Scripts
# Original repo: https://git.example.com/sydlexius/PowerShell-Individual-Scripts.git

# NOTE: Requires external repo at D:\dev\repos\Office-Language-Pack-Switcher
# Original repo: https://git.example.com/sydlexius/Office-Language-Pack-Switcher.git

# NOTE: Requires external repo at D:\dev\repos\Legacy-VBScript-Collection
# Original repo: https://git.example.com/sydlexius/Legacy-VBScript-Collection.git

#Requires -Version 5.1
<#
.SYNOPSIS
    Pre-migration setup and validation script
    
.DESCRIPTION
    This script prepares your system for the OneDrive to Git migration by:
    - Checking prerequisites
    - Setting up Gitea authentication
    - Creating necessary directories
    - Validating the migration plan
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$GiteaServerUrl = "https://git.example.com/",
    
    [Parameter()]
    [string]$GitBaseDirectory = "D:\Dev\PowerShell-Projects",
    
    [Parameter()]
    [string]$WorkspaceDirectory = "D:\Dev\VSCode-Workspaces"
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

function Test-Prerequisites {
    Write-Host "`n🔍 Checking Prerequisites..." -ForegroundColor Cyan
    
    $allGood = $true
    
    # Check Git installation
    try {
        $gitVersion = git --version
        Write-StatusMessage "Git installed: $gitVersion" "SUCCESS"
    }
    catch {
        Write-StatusMessage "Git not found. Please install Git from https://git-scm.com/" "ERROR"
        $allGood = $false
    }
    
    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -ge 5) {
        Write-StatusMessage "PowerShell version: $($PSVersionTable.PSVersion)" "SUCCESS"
    }
    else {
        Write-StatusMessage "PowerShell 5.1 or higher required" "ERROR"
        $allGood = $false
    }
    
    # Check internet connectivity to Gitea
    try {
        $response = Invoke-WebRequest -Uri $GiteaServerUrl -UseBasicParsing -TimeoutSec 10
        Write-StatusMessage "Gitea server accessible: $GiteaServerUrl" "SUCCESS"
    }
    catch {
        Write-StatusMessage "Cannot reach Gitea server: $GiteaServerUrl" "ERROR"
        $allGood = $false
    }
    
    # Check source directory
    $sourceDir = "d:\OneDrive - Doxazo\Documents\PowerShell\Scripts"
    if (Test-Path $sourceDir) {
        Write-StatusMessage "Source directory found: $sourceDir" "SUCCESS"
    }
    else {
        Write-StatusMessage "Source directory not found: $sourceDir" "ERROR"
        $allGood = $false
    }
    
    # Check available disk space
    $drive = Split-Path $GitBaseDirectory -Qualifier
    $driveInfo = Get-WmiObject -Class Win32_LogicalDisk | Where-Object DeviceID -eq $drive
    $freeSpaceGB = [math]::Round($driveInfo.FreeSpace / 1GB, 2)
    
    if ($freeSpaceGB -gt 5) {
        Write-StatusMessage "Available disk space on $drive : $freeSpaceGB GB" "SUCCESS"
    }
    else {
        Write-StatusMessage "Low disk space on $drive : $freeSpaceGB GB (recommend at least 5GB)" "WARNING"
    }
    
    return $allGood
}

function Get-GiteaAuthSetup {
    Write-Host "`n🔑 Gitea Authentication Setup" -ForegroundColor Cyan
    Write-Host "To proceed with the migration, you need:" -ForegroundColor White
    Write-Host "1. A Gitea account on $GiteaServerUrl" -ForegroundColor White
    Write-Host "2. A Personal Access Token with repository creation permissions" -ForegroundColor White
    
    Write-Host "`nTo create a Personal Access Token:" -ForegroundColor Yellow
    Write-Host "1. Log into your Gitea instance: $GiteaServerUrl" -ForegroundColor White
    Write-Host "2. Go to Settings > Applications" -ForegroundColor White
    Write-Host "3. Generate New Token" -ForegroundColor White
    Write-Host "4. Give it a name like 'PowerShell Migration'" -ForegroundColor White
    Write-Host "5. Select permissions: 'write:repository'" -ForegroundColor White
    Write-Host "6. Copy the generated token" -ForegroundColor White
    
    $username = Read-Host "`nEnter your Gitea username"
    $token = Read-Host "Enter your Gitea Personal Access Token" -AsSecureString
    
    # Convert SecureString to plain text for validation
    $tokenPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($token))
    
    # Test the credentials
    try {
        $headers = @{
            "Authorization" = "token $tokenPlain"
            "Content-Type" = "application/json"
        }
        
        $response = Invoke-RestMethod -Uri "$GiteaServerUrl/api/v1/user" -Headers $headers
        Write-StatusMessage "Authentication successful for user: $($response.login)" "SUCCESS"
        
        return @{
            Username = $username
            Token = $tokenPlain
            Valid = $true
        }
    }
    catch {
        Write-StatusMessage "Authentication failed: $($_.Exception.Message)" "ERROR"
        return @{
            Username = $username
            Token = $tokenPlain
            Valid = $false
        }
    }
}

function Show-MigrationPlan {
    Write-Host "`n📋 Migration Plan" -ForegroundColor Cyan
    
    $sourceDir = "d:\OneDrive - Doxazo\Documents\PowerShell\Scripts"
    $directories = Get-ChildItem -Path $sourceDir -Directory | 
        Where-Object { $_.Name -notlike ".*" -and $_.Name -notin @("InstalledScriptInfos", "New folder", "logs", "nppBackup") }
    
    Write-Host "The following directories will be migrated:" -ForegroundColor White
    
    $totalFiles = 0
    foreach ($dir in $directories) {
        $fileCount = (Get-ChildItem $dir.FullName -Recurse -File | Measure-Object).Count
        $totalFiles += $fileCount
        
        $repoName = $dir.Name
        if ($dir.Name -eq "Individual Scripts") { $repoName = "PowerShell-Individual-Scripts" }
        elseif ($dir.Name -eq "Legacy-VBScript") { $repoName = "Legacy-VBScript-Collection" }
        elseif ($dir.Name -eq "Office Language Pack Switcher") { $repoName = "Office-Language-Pack-Switcher" }
        elseif ($dir.Name -eq "Windows Secure Host Baseline") { $repoName = "Windows-Secure-Host-Baseline" }
        
        $status = if ($fileCount -gt 100) { " (Large)" } elseif ($fileCount -eq 0) { " (Empty)" } else { "" }
        Write-Host "  📁 $($dir.Name) -> $repoName ($fileCount files)$status" -ForegroundColor White
    }
    
    Write-Host "`nTotal: $($directories.Count) repositories, $totalFiles files" -ForegroundColor Yellow
    
    Write-Host "`nNew directory structure will be:" -ForegroundColor White
    Write-Host "  📁 $GitBaseDirectory\" -ForegroundColor Cyan
    foreach ($dir in $directories) {
        $repoName = $dir.Name -replace " ", "-"
        Write-Host "    📁 $repoName\" -ForegroundColor White
    }
    
    Write-Host "`n  📁 $WorkspaceDirectory\" -ForegroundColor Cyan
    $workspaces = Get-ChildItem -Path $sourceDir -Filter "*.code-workspace"
    foreach ($workspace in $workspaces) {
        Write-Host "    📄 $($workspace.Name)" -ForegroundColor White
    }
}

function New-DirectoryStructure {
    param([switch]$WhatIf)
    
    Write-Host "`n📁 Creating Directory Structure" -ForegroundColor Cyan
    
    $directories = @($GitBaseDirectory, $WorkspaceDirectory)
    
    foreach ($dir in $directories) {
        if ($WhatIf) {
            Write-StatusMessage "WHATIF: Would create directory: $dir"
        }
        else {
            if (!(Test-Path $dir)) {
                try {
                    New-Item -Path $dir -ItemType Directory -Force | Out-Null
                    Write-StatusMessage "Created directory: $dir" "SUCCESS"
                }
                catch {
                    Write-StatusMessage "Failed to create directory $dir : $($_.Exception.Message)" "ERROR"
                }
            }
            else {
                Write-StatusMessage "Directory already exists: $dir" "WARNING"
            }
        }
    }
}

function Start-PreMigrationSetup {
    Write-Host "🚀 PowerShell Scripts Migration - Pre-Migration Setup" -ForegroundColor Green
    Write-Host "=" * 60 -ForegroundColor Green
    
    # Check prerequisites
    $prereqsOk = Test-Prerequisites
    
    if (!$prereqsOk) {
        Write-Host "`n❌ Prerequisites check failed. Please resolve the issues above before proceeding." -ForegroundColor Red
        return
    }
    
    # Show migration plan
    Show-MigrationPlan
    
    # Get user confirmation
    Write-Host "`n❓ Do you want to proceed with the migration setup?" -ForegroundColor Yellow
    $confirm = Read-Host "Type 'yes' to continue"
    
    if ($confirm -ne "yes") {
        Write-Host "Migration setup cancelled." -ForegroundColor Yellow
        return
    }
    
    # Setup Gitea authentication
    $authInfo = Get-GiteaAuthSetup
    
    if (!$authInfo.Valid) {
        Write-Host "`n❌ Authentication setup failed. Please check your credentials." -ForegroundColor Red
        return
    }
    
    # Create directory structure
    New-DirectoryStructure
    
    # Generate the final migration command
    Write-Host "`n✅ Pre-migration setup complete!" -ForegroundColor Green
    Write-Host "`nTo start the migration, run:" -ForegroundColor Cyan
    Write-Host ".\Migrate-ToGitRepositories.ps1 -GiteaUsername '$($authInfo.Username)' -GiteaToken '$($authInfo.Token)' -WhatIf" -ForegroundColor White
    Write-Host "`nRemove -WhatIf when you're ready to perform the actual migration." -ForegroundColor Yellow
    
    Write-Host "`n⚠️  Important Notes:" -ForegroundColor Yellow
    Write-Host "1. The migration will copy files, not move them (original files remain)" -ForegroundColor White
    Write-Host "2. Test the migration with -WhatIf first" -ForegroundColor White
    Write-Host "3. Ensure you have backup of your OneDrive data" -ForegroundColor White
    Write-Host "4. The migration may take several minutes depending on file count" -ForegroundColor White
}

# Execute setup
Start-PreMigrationSetup




