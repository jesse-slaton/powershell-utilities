# Thin wrappers around the Windows Installer COM object. Every COM call in MsiTools goes
# through these functions so tests can mock them (the COM class exists only on Windows).

function Get-MsiInstallerObject {
    <#
    .SYNOPSIS
        Creates the WindowsInstaller.Installer COM object.

    .DESCRIPTION
        Returns a new WindowsInstaller.Installer COM object. Private to MsiTools.

    .EXAMPLE
        $installer = Get-MsiInstallerObject

    .NOTES
        Windows only (COM).
    #>
    [CmdletBinding()]
    param()

    New-Object -ComObject WindowsInstaller.Installer
}

function Invoke-MsiComMember {
    <#
    .SYNOPSIS
        Calls a method or reads a property on a Windows Installer COM object by late binding.

    .DESCRIPTION
        Uses Type.InvokeMember, because the Windows Installer objects expose no type
        information to the PowerShell adapter, so $object.Method() fails. Returns
        whatever the member returns. Private to MsiTools.

    .PARAMETER Target
        The COM object (Installer, Database, View or Record).

    .PARAMETER Name
        The member name, such as OpenDatabase, OpenView, Execute, Fetch, StringData or Close.

    .PARAMETER Kind
        InvokeMethod (the default) or GetProperty.

    .PARAMETER Arguments
        Arguments passed to the member.

    .EXAMPLE
        $view = Invoke-MsiComMember -Target $database -Name OpenView -Arguments 'SELECT * FROM Property'

    .EXAMPLE
        Invoke-MsiComMember -Target $record -Name StringData -Kind GetProperty -Arguments 1

    .NOTES
        Windows only (COM).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Target,

        [Parameter(Mandatory)]
        [string]$Name,

        [ValidateSet('InvokeMethod', 'GetProperty')]
        [string]$Kind = 'InvokeMethod',

        [object[]]$Arguments
    )

    # Unwrap PSObject wrappers first. Cmdlet output (Join-Path, Get-Item) arrives wrapped, and
    # InvokeMember is plain reflection, so the wrapper itself would reach COM, which rejects it
    # with DISP_E_TYPEMISMATCH. A value from a .NET method call is already unwrapped.
    $plainArguments = $null
    if ($null -ne $Arguments) {
        $plainArguments = [object[]]@(foreach ($argument in $Arguments) {
                if ($argument -is [psobject]) { $argument.psobject.BaseObject } else { $argument }
            })
    }
    $Target.GetType().InvokeMember($Name, $Kind, $null, $Target, $plainArguments)
}

function Close-MsiComObject {
    <#
    .SYNOPSIS
        Releases a Windows Installer COM object.

    .DESCRIPTION
        Calls Marshal.ReleaseComObject so the underlying handle (for a Database, the open
        .msi file) is freed immediately instead of at garbage collection. A $null input is
        ignored, so callers can release objects that were never created. Any other value that
        is not a COM object is not released: it gets a non-terminating error naming its type.
        ReleaseComObject would throw on it, and callers release in finally blocks, where that
        exception would replace the error that actually went wrong. Private to MsiTools.

    .PARAMETER InputObject
        The COM object to release (Installer, Database, View or Record), or $null.

    .EXAMPLE
        Close-MsiComObject -InputObject $database
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) { return }
    if (-not [System.Runtime.InteropServices.Marshal]::IsComObject($InputObject)) {
        $message = 'Not a COM object, so not released: {0}' -f $InputObject.GetType().FullName
        Write-Error -Message $message -Category InvalidArgument -TargetObject $InputObject
        return
    }
    $null = [System.Runtime.InteropServices.Marshal]::ReleaseComObject($InputObject)
}
