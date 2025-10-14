Function Reset-AclInheritance {
    <#
    .SYNOPSIS
    Resets all non-inherited ACEs and re-enables inheritance on an object's ACL. Will recursively apply these changes
    to any of the objects children if it's a container.

    .PARAMETER Path
    [String] The path to the object to reset.

    .EXAMPLE
    Reset-AclInheritance -Path "C:\temp"

    .NOTES
    This is similar to running the 'icacls.exe <FileName> /reset /t' operation but using .NET classes to run the
    operation instead. It is recommended that you have explicitly enabled the SeBackupPrivileges and SeRestorePrivilege
    privileges so that we can read and write the security descriptor for any object.
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