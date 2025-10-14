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
    Copies PowerShell script directories from OneDrive to individual Git repositories
    
.DESCRIPTION
    This script automates the copying of subdirectories from OneDrive to a new location
    where each directory becomes its own Git repository, then pushes to Gitea.
    The original files in OneDrive will remain intact for manual deletion later.
    
.PARAMETER GitBaseDirectory
    The base directory where Git repositories will be created (default: D:\Dev\PowerShell-Projects)
    
.PARAMETER GiteaServerUrl
    The Gitea server URL (default: https://git.example.com/)
    
.PARAMETER WhatIf
    Shows what would be done without actually performing the copying
    
.EXAMPLE
    .\Migrate-ToGitRepositories.ps1 -WhatIf
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$GitBaseDirectory = "D:\Dev\PowerShell-Projects",
    
    [Parameter()]
    [string]$GiteaServerUrl = "https://git.example.com/",
    
    [Parameter()]
    [switch]$WhatIf
)

# Script variables that will be populated via prompts
[string]$script:GiteaUsername = ""
[string]$script:GiteaToken = ""

# Configuration
$SourceDirectory = "d:\OneDrive - Doxazo\Documents\PowerShell\Scripts"
$WorkspaceDirectory = "D:\Dev\VSCode-Workspaces"

# Directories to exclude from copying
$ExcludeDirectories = @(
    ".venv",
    "InstalledScriptInfos", 
    "New folder",
    "logs",
    "nppBackup"
)

# Directory mapping for renaming during copying
$DirectoryRenames = @{
    "Individual Scripts" = "PowerShell-Individual-Scripts"
    "Legacy-VBScript" = "Legacy-VBScript-Collection"
    "Office Language Pack Switcher" = "Office-Language-Pack-Switcher"
    "Windows Secure Host Baseline" = "Windows-Secure-Host-Baseline"
}

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

function Get-UserCredentials {
    Write-StatusMessage "Please provide your Gitea credentials" "INFO"
    
    # Prompt for username
    $script:GiteaUsername = Read-Host -Prompt "Enter your Gitea username"
    while (-not $script:GiteaUsername) {
        Write-StatusMessage "Username cannot be empty!" "ERROR"
        $script:GiteaUsername = Read-Host -Prompt "Enter your Gitea username"
    }
    
    # Prompt for token with masking
    $secureToken = Read-Host -Prompt "Enter your Gitea personal access token" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
    $script:GiteaToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    
    while (-not $script:GiteaToken) {
        Write-StatusMessage "Token cannot be empty!" "ERROR"
        $secureToken = Read-Host -Prompt "Enter your Gitea personal access token" -AsSecureString
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
        $script:GiteaToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    }
    
    Write-StatusMessage "Credentials received. Using username: $script:GiteaUsername" "SUCCESS"
}

function Test-GitInstallation {
    try {
        $gitVersion = git --version
        Write-StatusMessage "Git found: $gitVersion" "SUCCESS"
        return $true
    }
    catch {
        Write-StatusMessage "Git not found. Please install Git first." "ERROR"
        return $false
    }
}

function New-GiteaRepository {
    param(
        [string]$RepositoryName,
        [string]$Description = ""
    )
    
    if ($WhatIf) {
        Write-StatusMessage "WHATIF: Would create Gitea repository: $RepositoryName"
        return $true
    }
    
    $headers = @{
        "Authorization" = "token $GiteaToken"
        "Content-Type" = "application/json"
    }
    
    $body = @{
        "name" = $RepositoryName
        "description" = $Description
        "private" = $false
        "auto_init" = $false
    } | ConvertTo-Json
      try {
        Invoke-RestMethod -Uri "$GiteaServerUrl/api/v1/user/repos" -Method POST -Headers $headers -Body $body | Out-Null
        Write-StatusMessage "Created Gitea repository: $RepositoryName" "SUCCESS"
        return $true
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 409) {
            Write-StatusMessage "Repository $RepositoryName already exists" "WARNING"
            return $true
        }
        Write-StatusMessage "Failed to create repository $RepositoryName : $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Copy-DirectoryStructure {
    param(
        [string]$Source,
        [string]$Destination
    )
    
    if ($WhatIf) {
        Write-StatusMessage "WHATIF: Would copy $Source to $Destination"
        return
    }
    
    if (!(Test-Path $Destination)) {
        New-Item -Path $Destination -ItemType Directory -Force | Out-Null
    }
    
    Write-StatusMessage "Copying files from $Source to $Destination"
      # Use robocopy for efficient copying with proper path handling
    $robocopyArgs = @(
        "`"$Source`"",
        "`"$Destination`"",
        "/E",       # Copy subdirectories including empty ones
        "/COPY:DAT", # Copy Data, Attributes, and Timestamps (no security info)
        "/R:3",     # Retry 3 times
        "/W:10",    # Wait 10 seconds between retries
        "/NP",      # No progress
        "/NFL",     # No file list
        "/NDL",     # No directory list
        "/MT:8"     # Multi-threaded with 8 threads
    )
    
    Write-StatusMessage "Running: robocopy $($robocopyArgs -join ' ')"
    
    try {
        $result = Start-Process -FilePath "robocopy" -ArgumentList $robocopyArgs -Wait -PassThru -NoNewWindow
        
        # Robocopy exit codes 0-3 are success
        if ($result.ExitCode -le 3) {
            Write-StatusMessage "Successfully copied directory structure (Exit code: $($result.ExitCode))" "SUCCESS"
        } else {
            throw "Robocopy failed with exit code: $($result.ExitCode)"
        }
    }
    catch {
        Write-StatusMessage "Robocopy error: $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Initialize-GitRepository {
    param(
        [string]$RepositoryPath,
        [string]$RepositoryName,
        [string]$RemoteUrl
    )
    
    if ($WhatIf) {
        Write-StatusMessage "WHATIF: Would initialize Git repository in $RepositoryPath"
        return
    }
      Write-StatusMessage "Initializing Git repository in $RepositoryPath"    Push-Location $RepositoryPath
    try {
        # Set environment variables to disable interactive authentication
        $env:GIT_TERMINAL_PROMPT = "0"
        $env:GCM_INTERACTIVE = "never"
        $env:GCM_GUI_PROMPT = "never"
        $env:GIT_ASKPASS = "echo"
        
        # Check if already a git repository
        if (Test-Path ".git") {
            Write-StatusMessage "Git repository already exists, cleaning up..." "WARNING"
            Remove-Item ".git" -Recurse -Force
        }
        
        # Initialize Git repository
        $initResult = git init 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Git init failed: $initResult"
        }
        
        # Configure credential helper after repository initialization
        git config --local credential.helper ""
        git config --local credential.helper store
        git config --local credential.useHttpPath true
        
        # Set default branch to main
        git branch -M main 2>&1
        
        # Create .gitignore
        $gitignoreContent = @"
# PowerShell
*.ps1xml
pester-tests.xml

# Logs
*.log
logs/

# Temporary files
*.tmp
*.temp

# Windows
Thumbs.db
ehthumbs.db
Desktop.ini
`$RECYCLE.BIN/

# IDE
.vscode/settings.json
*.swp
*.swo

# Credentials
*credential*
*password*
*secret*
*.pfx
*.p12
"@
        $gitignoreContent | Out-File -FilePath ".gitignore" -Encoding UTF8
        
        # Create README.md
        $readmeContent = @"
# $RepositoryName

PowerShell scripts and tools for $($RepositoryName -replace '-', ' ').

## Description

This repository contains PowerShell scripts copied from a centralized script collection.

## Usage

[Add usage instructions here]

## Requirements

- PowerShell 5.1 or later
- [Add other requirements as needed]

## Contributing

[Add contribution guidelines if needed]
"@
        $readmeContent | Out-File -FilePath "README.md" -Encoding UTF8
        
        # Stage all files
        git add . 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Git add failed"
        }
          # Initial commit
        git commit -m "Initial commit: Copied from centralized script collection" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Git commit failed"
        }        # Add remote (use the authenticated URL directly)
        git remote add origin $RemoteUrl 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-StatusMessage "Warning: Could not add remote origin: $RemoteUrl" "WARNING"
        }
        
        # Push to remote (credentials are embedded in the URL)
        Write-StatusMessage "Pushing to remote repository..."
        git push -u origin main 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Git push failed - repository created locally but not pushed to remote"
        }
        
        Write-StatusMessage "Git repository initialized and pushed successfully" "SUCCESS"
    }
    catch {
        Write-StatusMessage "Failed to initialize Git repository: $($_.Exception.Message)" "ERROR"
        throw
    }
    finally {
        Pop-Location
    }
}

function Update-VSCodeWorkspace {
    param(
        [string]$WorkspaceFile,
        [hashtable]$RepositoryMappings
    )
    
    if ($WhatIf) {
        Write-StatusMessage "WHATIF: Would update VSCode workspace: $WorkspaceFile"
        return
    }
    
    if (!(Test-Path $WorkspaceFile)) {
        Write-StatusMessage "Workspace file not found: $WorkspaceFile" "WARNING"
        return
    }
    
    try {
        $workspace = Get-Content $WorkspaceFile | ConvertFrom-Json
        
        # Update folder paths
        foreach ($folder in $workspace.folders) {
            $folderName = Split-Path $folder.path -Leaf
            if ($RepositoryMappings.ContainsKey($folderName)) {
                $newPath = $RepositoryMappings[$folderName]
                Write-StatusMessage "Updating workspace path: $($folder.path) -> $newPath"
                $folder.path = $newPath
            }
        }
        
        # Save updated workspace
        $workspace | ConvertTo-Json -Depth 10 | Out-File $WorkspaceFile -Encoding UTF8
        Write-StatusMessage "Updated VSCode workspace: $WorkspaceFile" "SUCCESS"
    }
    catch {
        Write-StatusMessage "Failed to update workspace $WorkspaceFile : $($_.Exception.Message)" "ERROR"
    }
}

# Main execution
function Start-CopyOperation {
    try {
        Write-StatusMessage "Starting copying from OneDrive to Git repositories" "INFO"
        
        # Prompt for credentials
        Get-UserCredentials
        
        # Validate prerequisites
        if (!(Test-GitInstallation)) {
            return
        }
        
        if (!(Test-Path $SourceDirectory)) {
            Write-StatusMessage "Source directory not found: $SourceDirectory" "ERROR"
            return
        }
    
    # Create base directories
    if (!$WhatIf) {
        if (!(Test-Path $GitBaseDirectory)) {
            New-Item -Path $GitBaseDirectory -ItemType Directory -Force | Out-Null
            Write-StatusMessage "Created base directory: $GitBaseDirectory" "SUCCESS"
        }
        
        if (!(Test-Path $WorkspaceDirectory)) {
            New-Item -Path $WorkspaceDirectory -ItemType Directory -Force | Out-Null
            Write-StatusMessage "Created workspace directory: $WorkspaceDirectory" "SUCCESS"
        }
    }
    
    # Get directories to copy
    $sourceDirectories = Get-ChildItem -Path $SourceDirectory -Directory | 
        Where-Object { $_.Name -notin $ExcludeDirectories -and $_.Name -notlike ".*" }
    
    $repositoryMappings = @{}
    $migrationResults = @()
    
    foreach ($directory in $sourceDirectories) {
        $originalName = $directory.Name
        $repositoryName = if ($DirectoryRenames.ContainsKey($originalName)) {
            $DirectoryRenames[$originalName]
        } else {
            $originalName
        }        $sourcePath = $directory.FullName
        $destinationPath = Join-Path $GitBaseDirectory $repositoryName
        # Use standard Git URL format with embedded credentials
        $remoteUrl = "$($GiteaServerUrl.TrimEnd('/'))/$GiteaUsername/$repositoryName.git"
        $authRemoteUrl = $remoteUrl -replace "https://", "https://$($GiteaUsername):$($GiteaToken)@"
        
        $repositoryMappings[$originalName] = $destinationPath
        
        Write-StatusMessage "Processing: $originalName -> $repositoryName"
        
        try {
            # Create Gitea repository
            $repoCreated = New-GiteaRepository -RepositoryName $repositoryName -Description "PowerShell scripts for $originalName"
            
            if ($repoCreated) {
                # Copy directory structure
                Copy-DirectoryStructure -Source $sourcePath -Destination $destinationPath
                  # Initialize Git repository
                Initialize-GitRepository -RepositoryPath $destinationPath -RepositoryName $repositoryName -RemoteUrl $authRemoteUrl
                
                $migrationResults += [PSCustomObject]@{
                    Original = $originalName
                    Repository = $repositoryName
                    Path = $destinationPath
                    Status = "Success"
                    Error = $null
                }
                
                Write-StatusMessage "Successfully copied: $originalName" "SUCCESS"
            }
        }
        catch {
            $migrationResults += [PSCustomObject]@{
                Original = $originalName
                Repository = $repositoryName
                Path = $destinationPath
                Status = "Failed"
                Error = $_.Exception.Message
            }
            
            Write-StatusMessage "Failed to copy $originalName : $($_.Exception.Message)" "ERROR"
        }
    }
    
    # Copy and update workspace files
    Write-StatusMessage "Updating VSCode workspaces"
    $workspaceFiles = Get-ChildItem -Path $SourceDirectory -Filter "*.code-workspace"
    
    foreach ($workspaceFile in $workspaceFiles) {
        $newWorkspacePath = Join-Path $WorkspaceDirectory $workspaceFile.Name
        
        if (!$WhatIf) {
            Copy-Item $workspaceFile.FullName $newWorkspacePath -Force
        }
        
        Update-VSCodeWorkspace -WorkspaceFile $newWorkspacePath -RepositoryMappings $repositoryMappings
    }
    
    # Generate summary report
    Write-StatusMessage "Copy Summary:" "INFO"
    $successful = ($migrationResults | Where-Object Status -eq "Success").Count
    $failed = ($migrationResults | Where-Object Status -eq "Failed").Count
    
    Write-Host "`n📊 Copy Results:" -ForegroundColor Cyan
    Write-Host "✅ Successful: $successful" -ForegroundColor Green
    Write-Host "❌ Failed: $failed" -ForegroundColor Red
      if ($failed -gt 0) {
        Write-Host "`n❌ Failed Copy Operations:" -ForegroundColor Red
        $migrationResults | Where-Object Status -eq "Failed" | ForEach-Object {
            Write-Host "  - $($_.Original): $($_.Error)" -ForegroundColor Red
        }
    }
    
    Write-Host "`n📁 New Repository Locations:" -ForegroundColor Cyan
    $migrationResults | Where-Object Status -eq "Success" | ForEach-Object {
        Write-Host "  - $($_.Repository): $($_.Path)" -ForegroundColor White
    }
    
    Write-Host "`n🔧 VSCode Workspaces updated in: $WorkspaceDirectory" -ForegroundColor Cyan
      if (!$WhatIf) {
        Write-Host "`n⚠️  Next Steps:" -ForegroundColor Yellow
        Write-Host "1. Review the copied repositories in: $GitBaseDirectory" -ForegroundColor White
        Write-Host "2. Open VSCode workspaces from: $WorkspaceDirectory" -ForegroundColor White
        Write-Host "3. Test that all repositories are working correctly" -ForegroundColor White        Write-Host "4. Manually delete the original files from OneDrive after verification" -ForegroundColor White
    }
    }
    catch {
        Write-StatusMessage "Critical error during copy operation: $($_.Exception.Message)" "ERROR"
        throw
    }
}

# Execute migration
Start-CopyOperation




