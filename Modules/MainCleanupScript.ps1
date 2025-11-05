<#
.SYNOPSIS
    Executes system cleanup tasks with configurable thoroughness levels.

.DESCRIPTION
    MainCleanupScript.ps1 performs various system cleanup operations including recycle bin,
    temporary files, DISM cleanup, and CCM cache cleanup. The script supports different
    thoroughness levels and can resume from the last completed step. Cleanup tasks are
    executed as background jobs with configurable timeouts based on the thoroughness level.

.PARAMETER Thoroughness
    Specifies the level of cleanup to perform. Valid values are:
    - fast: Quick cleanup (15 min timeout) - Recycle bin and CCM cache only
    - normal: Standard cleanup (60 min timeout) - Adds temporary files cleanup
    - thorough: Deep cleanup (6 hour timeout) - Adds DISM cleanup
    - unrestricted: Comprehensive cleanup (no timeout) - All cleanup operations
    Default value is "normal".

.PARAMETER Resume
    When specified, the script will resume from the last completed cleanup step.
    This is useful if a previous cleanup operation was interrupted or timed out.

.EXAMPLE
    .\MainCleanupScript.ps1
    Runs the cleanup script with default (normal) thoroughness level.

.EXAMPLE
    .\MainCleanupScript.ps1 -Thoroughness fast
    Performs a quick cleanup including recycle bin and CCM cache with a 15-minute timeout.

.EXAMPLE
    .\MainCleanupScript.ps1 -Thoroughness thorough
    Performs a deep cleanup including DISM with a 6-hour timeout.

.EXAMPLE
    .\MainCleanupScript.ps1 -Resume
    Resumes cleanup from the last completed step using normal thoroughness.

.NOTES
    Author: System Administrator
    Dependencies: Requires CleanupFunctions.psm1 module in the same directory
    Log Location: C:\Contoso\Logs
    Registry: Stores cleanup state in registry when disk space is below 15%

.LINK
    CleanupFunctions.psm1
#>

param (
    [ValidateSet("fast", "normal", "thorough", "unrestricted")]
    [string]$Thoroughness = "normal",
    [switch]$Resume
)

# Import the cleanup module
$modulePath = ".\CleanupFunctions.psm1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Verbose
}
else {
    Write-Error "Module path '$modulePath' not found."
    exit
}

$StartTime = Get-Date
$LogPath = "C:\Contoso\Logs"
StartCleanupLog -LogPath $LogPath -Thoroughness $Thoroughness -StartTime $StartTime

try {
    $LastCompletedStep = if ($Resume) { GetLastCompletedStep } else { $null }
    $jobTimeoutSeconds = switch ($Thoroughness) {
        "fast" { 900 } # 15 minutes
        "normal" { 3600 } # 60 minutes
        "thorough" { 21600 } # 6 hours
        "unrestricted" { 0 } # Unlimited
    }

    # Define a script block for the cleanup tasks
    $cleanupTasks = {
        param($Thoroughness, $LastCompletedStep)
        # Import the module within the job
        Import-Module $using:modulePath

        # Execute cleanup tasks based on thoroughness level
        switch ($Thoroughness) {
            "fast" {
                CleanRecycleBin
                InvokeCCMCacheCleanup -Thoroughness $Thoroughness
                # Additional fast cleanup logic
            }
            "normal" {
                CleanRecycleBin
                CleanTemporaryFiles
                InvokeCCMCacheCleanup -Thoroughness $Thoroughness
                # Additional normal cleanup logic
            }
            {($_ -eq "thorough") -or ($_ -eq "unrestricted") } {
                CleanRecycleBin
                CleanTemporaryFiles
                InvokeDISM
                InvokeCCMCacheCleanup -Thoroughness $Thoroughness
                # Additional thorough/unrestricted cleanup logic
            }
        }
    }

    # Start cleanup tasks as a job
    $job = Start-Job -ScriptBlock $cleanupTasks -ArgumentList $Thoroughness, $LastCompletedStep

    if ($jobTimeoutSeconds -gt 0) {
        # Wait for the job to complete with a timeout
        $result = Wait-Job -Job $job -Timeout $jobTimeoutSeconds
        if (-not $result) {
            Write-Host "Cleanup process exceeded the maximum allowed time for $Thoroughness."
            # Consider adding logic to handle a timeout scenario, such as logging or cleanup.
        }
    }
    else {
        # For unrestricted, wait indefinitely until the job completes
        Wait-Job -Job $job
    }

    # Receive job results
    Receive-Job -Job $job

    $CleanupCompletedIndicator = $true
}
catch {
    Write-Host "An error occurred: $_"
    $CleanupCompletedIndicator = $false
}
finally {
    Stop-CleanupLog

    $finalFreeSpacePercentage = (Get-PSDrive C).Free / ((Get-PSDrive C).Free + (Get-PSDrive C).Used) * 100
    if ($finalFreeSpacePercentage -lt 15) {
        Set-RegistryValues -Thoroughness $Thoroughness -StartTime $StartTime -CleanupCompleted ($CleanupCompletedIndicator -as [int]) -LastCompleted $global:LastCompletedStep
    }
    else {
        Remove-RegistryValues
    }

    # Cleanup the job
    Remove-Job -Job $job -Force
}
