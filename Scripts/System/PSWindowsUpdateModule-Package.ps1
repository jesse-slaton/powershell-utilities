If (Get-Module -ListAvailable -Name PSWindowsUpdate) { Write-Output "PSWindowsUpdate Module is Already Installed." }
Else {
    $webclient = New-Object System.Net.WebClient
    $webclient.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NetFramework\v4.0.30319' -Name 'SchUseStrongCrypto' -Value '1' -Type DWord
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NetFramework\v4.0.30319' -Name 'SchUseStrongCrypto' -Value '1' -Type DWord 
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-PackageProvider NuGet -Force;
    Register-PSRepository -Name "PSGallery" –SourceLocation "https://www.powershellgallery.com/api/v2/" -InstallationPolicy Trusted        
    #Set-PSRepository PSGallery -InstallationPolicy Trusted
    Install-Module PSWindowsUpdate -Force -Confirm:$false
}
