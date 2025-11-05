Function Reset-AclInheritance {
    <#
    .SYNOPSIS
    Resets all non-inherited ACEs and re-enables inheritance on an object's ACL.

    .DESCRIPTION
    This function removes all non-inherited Access Control Entries (ACEs) from a file or folder's
    Access Control List (ACL) and re-enables inheritance. If the target is a container (folder),
    the function will recursively apply these changes to all child objects. This is equivalent to
    running 'icacls.exe /reset /t' but using PowerShell .NET classes for better error handling
    and integration.

    .PARAMETER Path
    The path to the file or folder to reset. This parameter is mandatory.
    Supports both file system paths and registry paths.

    .EXAMPLE
    Reset-AclInheritance -Path "C:\temp"
    Resets ACL inheritance for the C:\temp folder and all its contents.

    .EXAMPLE
    Reset-AclInheritance -Path "C:\MyFile.txt" -Verbose
    Resets ACL inheritance for a single file with detailed progress output.

    .EXAMPLE
    Reset-AclInheritance -Path "C:\SecureFolder" -WhatIf
    Shows what would happen if you reset the ACL without actually making changes.

    .NOTES
    Author: System Administrator
    Purpose: ACL management and security remediation
    Requires: Administrator privileges, SeBackupPrivilege and SeRestorePrivilege recommended
    Similar to: icacls.exe <Path> /reset /t

    .LINK
    Get-Acl
    Set-Acl
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)] [String]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Error -Message "The object at '$Path' does not exist"
        return
    }

    Write-Verbose -Message "Getting security descriptor for item at '$Path'"
    $security_descriptor = Get-Acl -LiteralPath $Path
    $changed = $false

    if ($security_descriptor.AreAccessRulesProtected) {
        Write-Verbose -Message "Object at '$Path' has disabled inheritance, re-enabling it"
        $security_descriptor.SetAccessRuleProtection($false, $false)
        $changed = $true
    }

    $acls = $security_descriptor.GetAccessRules($true, $false, [System.Security.Principal.NTAccount])
    foreach ($ace in $acls) {
        $ace_string = "$($ace.IdentityReference.Value): $($ace.AccessControlType.ToString()) ($($ace.FileSystemRights.ToString()))"
        Write-Verbose -Message "Removing non-inherited ACE at '$Path' - $ace_string"
        $result = $security_descriptor.RemoveAccessRule($ace)
        if (-not $result) {
            Write-Error -Message "Failed to remove non-inherited ACE at '$Path' - $ace_string"
        }
        else {
            $changed = $true
        }
    }

    if ($changed) {
        if ($PSCmdlet.ShouldProcess($Path, "Persisting new security descriptor that has been reset")) {
            Write-Verbose -Message "Setting new security descriptor for item at '$Path'"
            Set-Acl -LiteralPath $Path -AclObject $security_descriptor
        }
        else {
            Write-Verbose -Message "What if: Setting new security descriptor for item at '$Path'"
        }
    }
    else {
        Write-Verbose -Message "No changes required to the security descriptor for item at '$Path'"
    }

    if (Test-Path -LiteralPath $Path -PathType Container) {
        Get-ChildItem -LiteralPath $Path | ForEach-Object { Reset-AclInheritance -Path $_.FullName }
    }
}