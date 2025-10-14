function Get-PowerShellType {
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