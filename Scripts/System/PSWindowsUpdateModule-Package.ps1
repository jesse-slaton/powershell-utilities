<#
.SYNOPSIS
    Installs the PSWindowsUpdate module from the PowerShell Gallery if it is not already installed.

.DESCRIPTION
    If Get-Module -ListAvailable finds PSWindowsUpdate, writes
    "PSWindowsUpdate Module is Already Installed." and does nothing else.

    Otherwise it:
    - sets the default network credentials on the default web proxy for this session;
    - sets SchUseStrongCrypto = 1 (DWORD) under both the 64-bit and 32-bit
      HKLM .NETFramework\v4.0.30319 keys (a persistent, machine-wide change);
    - switches the session to TLS 1.2;
    - installs the NuGet package provider (-Force);
    - runs Register-PSRepository for PSGallery as a trusted repository;
    - runs Install-Module PSWindowsUpdate -Force.

    PSGallery is usually registered already, in which case Register-PSRepository writes
    an error and the script continues to Install-Module.

.EXAMPLE
    .\PSWindowsUpdateModule-Package.ps1

    Installs PSWindowsUpdate, or reports that it is already installed.

.NOTES
    Requires administrator rights (HKLM changes and an all-users module install),
    Windows PowerShell 5.1 with PowerShellGet/PackageManagement, and internet access to
    www.powershellgallery.com (through the system proxy if one is configured).
#>

If (Get-Module -ListAvailable -Name PSWindowsUpdate) { Write-Output "PSWindowsUpdate Module is Already Installed." }
Else {
    $webclient = New-Object System.Net.WebClient
    $webclient.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NetFramework\v4.0.30319' -Name 'SchUseStrongCrypto' -Value '1' -Type DWord
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NetFramework\v4.0.30319' -Name 'SchUseStrongCrypto' -Value '1' -Type DWord 
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-PackageProvider NuGet -Force;
    Register-PSRepository -Name "PSGallery" -SourceLocation "https://www.powershellgallery.com/api/v2/" -InstallationPolicy Trusted        
    #Set-PSRepository PSGallery -InstallationPolicy Trusted
    Install-Module PSWindowsUpdate -Force -Confirm:$false
}
