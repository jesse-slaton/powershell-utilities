<#
.SYNOPSIS
    Defines Get-PowerShellType, which reports the PowerShell edition and platform in use.

.DESCRIPTION
    Running the script only defines the Get-PowerShellType function; it writes no output.
    Dot-source the script, then call the function.

    Get-PowerShellType reads $PSVersionTable and outputs one string:
    - DesktopWindows for PowerShell 2.0, 3.0 or 4.0, or when PSEdition is Desktop
    - CoreLinux, CoreMacOS or CoreWindows when PSEdition is Core, based on $IsLinux,
      $IsMacOS and $IsWindows
    With -Verbose it also writes the edition, version and OS. When none of these cases
    match (for example PowerShell 5.0, whose $PSVersionTable has no PSEdition), it
    outputs nothing. Read-only.

.EXAMPLE
    . .\Get-PowerShellType.ps1
    Get-PowerShellType

    DesktopWindows

.EXAMPLE
    . .\Get-PowerShellType.ps1
    Get-PowerShellType -Verbose

    Also writes the edition, version and OS as a verbose message.

.NOTES
    None.
#>


function Get-PowerShellType {
    <#
    .SYNOPSIS
        Reports the PowerShell edition and platform in use.

    .DESCRIPTION
        Reads $PSVersionTable and outputs DesktopWindows (PowerShell 2.0, 3.0, 4.0, or
        PSEdition Desktop), or CoreLinux, CoreMacOS or CoreWindows (PSEdition Core, based on
        $IsLinux, $IsMacOS and $IsWindows). Outputs nothing when no case matches, for
        example on PowerShell 5.0. With -Verbose it also writes the edition, version and OS.

    .EXAMPLE
        Get-PowerShellType

        DesktopWindows

    .EXAMPLE
        Get-PowerShellType -Verbose

        Also writes the edition, version and OS as a verbose message.

    .NOTES
        None.
    #>
    [cmdletbinding()]
    param ()

    if ($PSVersionTable.PSVersion -eq '2.0' -or $PSVersionTable.PSVersion -eq '3.0' -or $PSVersionTable.PSVersion -eq '4.0') {
        # Windows PowerShell desktop version 2.0 or 4.0 found
        Write-Verbose "Desktop $($PsVersionTable.PSVersion.tostring()) Windows"
        $PowerShellType = 'DesktopWindows'
    }
    else {
        switch ($PSVersionTable.PSEdition) {
            'Desktop' {
                # Windows PowerShell desktop version found
                Write-Verbose "$($PsVersionTable.PSEdition) $($PsVersionTable.PSVersion.tostring()) Windows"
                $PowerShellType = 'DesktopWindows'
            }
            'core' {
                if ($IsLinux) {
                    # PowerShell Core for Linux
                    Write-Verbose "$($PsVersionTable.PSEdition) $($PsVersionTable.PSVersion.tostring()) $($PsVersionTable.OS)"
                    $PowerShellType = 'CoreLinux'
                }
                if ($IsMacOS) {
                    # PowerShell Core for macOS
                    Write-Verbose "$($PsVersionTable.PSEdition) $($PsVersionTable.PSVersion.tostring()) $($PsVersionTable.OS)"
                    $PowerShellType = 'CoreMacOS'
                }
                if ($IsWindows) {
                    # PowerShell Core for Windows
                    Write-Verbose "$($PsVersionTable.PSEdition) $($PsVersionTable.PSVersion.tostring()) $($PsVersionTable.OS)"
                    $PowerShellType = 'CoreWindows'
                }
            }
        }
    }
    Write-Output $PowerShellType
}