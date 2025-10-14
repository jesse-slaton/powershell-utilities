<#
.SYNOPSIS
    Repairs specified types of malformed PATH environment variable entries, locally or remotely.

.DESCRIPTION
    This function repairs malformed entries in the PATH environment variable locally or on a remote machine based on the selected issue types.
    It addresses issues such as:
    - Unbalanced double-quotes
    - Incorrect semicolons after drive letters
    - Duplicate entries
    - Blank or empty entries
    - Non-existent directories

.PARAMETER ComputerName
    Specifies the remote computer name where the PATH entries will be fixed. If not specified, it will fix the local machine.

.PARAMETER Credentials
    Specifies the credentials to use for the remote connection. This is only required if a ComputerName is provided.

.PARAMETER WhatIf
    Simulates the operation without making any changes to the environment variable.

.PARAMETER Prompt
    Prompts the user for confirmation before each fix.

.PARAMETER FixTypes
    Specifies the types of issues to fix. Acceptable values are:
    - UnbalancedQuotes
    - IncorrectSemicolons
    - Duplicates
    - BlankEntries
    - NonExistentPaths
    Multiple values can be passed as an array.

.EXAMPLE
    Repair-PathEntries -FixTypes UnbalancedQuotes
    Fixes only unbalanced double quotes in the local machine's PATH variable.

.EXAMPLE
    Repair-PathEntries -FixTypes Duplicates,NonExistentPaths -ComputerName "RemotePC"
    Fixes duplicates and non-existent directories in the PATH variable on a remote machine named "RemotePC".

.EXAMPLE
    Repair-PathEntries -FixTypes UnbalancedQuotes -WhatIf
    Simulates fixing unbalanced quotes without making any changes on the local machine.

.EXAMPLE
    Repair-PathEntries -FixTypes IncorrectSemicolons,BlankEntries -ComputerName "RemotePC" -Credentials (Get-Credential)
    Fixes incorrect semicolons and blank entries on the remote machine "RemotePC", using the specified credentials.

#>

function Repair-PathEntries {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact="Medium")]
    param (
        [ValidateSet('UnbalancedQuotes', 'IncorrectSemicolons', 'Duplicates', 'BlankEntries', 'NonExistentPaths')]
        [string[]]$FixTypes = @('UnbalancedQuotes', 'IncorrectSemicolons', 'Duplicates', 'BlankEntries', 'NonExistentPaths'),

        [string]$ComputerName,

        [pscredential]$Credentials,

        [switch]$Prompt
    )

    # Define the core script logic
    $scriptBlock = {
        param($FixTypes, $WhatIf, $Prompt)
        
        try {
            # Get the original PATH variable as a raw string
            $pathRaw = [System.Environment]::GetEnvironmentVariable('PATH')

            if (-not $pathRaw) {
                throw "The PATH environment variable is empty or not set."
            }

            # Save a backup of the original PATH in a new environment variable called BADPATH (overwrite if exists)
            if ($PSCmdlet.ShouldProcess('Create/Overwrite BADPATH variable', 'Backup PATH')) {
                [System.Environment]::SetEnvironmentVariable('BADPATH', $pathRaw, [System.EnvironmentVariableTarget]::User)
            }

            # Create or overwrite the PATH_FIX_DATE environment variable with the current date and time
            $timestamp = Get-Date -Format 'yyyy-MM-dd_HH:mm:ss'
            [System.Environment]::SetEnvironmentVariable('PATH_FIX_DATE', $timestamp, [System.EnvironmentVariableTarget]::User)

            # Remove leading/trailing semicolons and split on semicolons outside quotes
            $pathRaw = $pathRaw.Trim(';')
            $pathEntries = [regex]::Split($pathRaw, '(?<!")\;(?!")')

            # Track seen entries to remove duplicates
            $seenPaths = @{}
            $fixedPath = @()

            foreach ($entry in $pathEntries) {
                $suggestedEntry = $entry
                $quoteCount = ($entry -split '"').Count - 1
                $issueFixed = $false

                # Fix unbalanced double-quotes if selected
                if ('UnbalancedQuotes' -in $FixTypes -and $quoteCount % 2 -ne 0) {
                    $suggestedEntry = $entry -replace '"', ''
                    $issueFixed = $true
                }

                # Fix incorrect semicolons if selected
                if ('IncorrectSemicolons' -in $FixTypes -and $entry -match '^[A-Z]:\\;') {
                    # Attempt to fix the path and test if the corrected path exists
                    $correctedPath = $entry -replace ':\;', ':\'
                    if (Test-Path $correctedPath) {
                        $suggestedEntry = $correctedPath
                        $issueFixed = $true
                    } else {
                        continue  # Skip invalid path
                    }
                }

                # Skip blank entries if selected
                if ('BlankEntries' -in $FixTypes -and [string]::IsNullOrWhiteSpace($entry)) {
                    continue
                }

                # Fix duplicates if selected (allow only one unique entry)
                if ('Duplicates' -in $FixTypes -and $seenPaths.ContainsKey($suggestedEntry)) {
                    continue  # Skip duplicate entries
                } else {
                    $seenPaths[$suggestedEntry] = $true
                }

                # Skip non-existent paths if selected
                if ('NonExistentPaths' -in $FixTypes -and -not [System.IO.Directory]::Exists($suggestedEntry.Trim('"')) -and $suggestedEntry -notmatch '^[A-Z]:\\$') {
                    continue  # Skip invalid or non-existent path
                }

                # Add the valid, corrected entry to the fixed PATH
                if ($WhatIf -or $Prompt) {
                    if ($Prompt) {
                        $confirmation = Read-Host "Do you want to apply the correction for '$suggestedEntry'? (Y/N)"
                        if ($confirmation -ne 'Y') {
                            continue
                        }
                    }

                    Write-Host "Would change: $entry -> $suggestedEntry" -ForegroundColor Yellow
                } else {
                    $fixedPath += $suggestedEntry
                }
            }

            if (-not $WhatIf) {
                # Join the corrected paths with semicolons and update the PATH environment variable
                $newPath = ($fixedPath -join ';').Trim(';')
                [System.Environment]::SetEnvironmentVariable('PATH', $newPath, [System.EnvironmentVariableTarget]::User)

                Write-Host "Original PATH backed up to BADPATH."
                Write-Host "New PATH applied successfully."
            }

        } catch {
            Write-Error "An error occurred while processing the PATH variable: $_"
        }
    }

    # If a remote ComputerName is specified, use Invoke-Command
    if ($ComputerName) {
        Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock -ArgumentList $FixTypes, $WhatIf, $Prompt -Credential $Credentials
    } else {
        # Run the script block locally
        & $scriptBlock $FixTypes $WhatIf $Prompt
    }
}
