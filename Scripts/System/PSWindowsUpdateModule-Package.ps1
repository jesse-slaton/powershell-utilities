<#
.SYNOPSIS
    Installs the PSWindowsUpdate module from the PowerShell Gallery if it is not already installed.

.DESCRIPTION
    If Get-Module -ListAvailable finds PSWindowsUpdate, writes
    "PSWindowsUpdate Module is Already Installed." and does nothing else.

    Otherwise it installs PSWindowsUpdate for all users from the PSGallery repository
    with Install-PSResource (PSResourceGet, built into PowerShell 7.4 and later),
    trusting PSGallery for this install only, and writes which command it used.
    Windows PowerShell 5.1 without PSResourceGet falls back to Install-Module -Force
    (which also bootstraps the NuGet provider). PowerShell 7 without PSResourceGet
    stops with an error instead of falling back.

    It changes no registry values or repository registrations. Only on the Windows
    PowerShell 5.1 Install-Module fallback does it add TLS 1.2 to the protocols this
    process may use (see .NOTES).

.EXAMPLE
    .\PSWindowsUpdateModule-Package.ps1

    Installs PSWindowsUpdate, or reports that it is already installed.

.NOTES
    Requires administrator rights (an all-users module install) and internet access
    to www.powershellgallery.com. Windows PowerShell 5.1 or PowerShell 7. PowerShell
    7.0 to 7.3 need the Microsoft.PowerShell.PSResourceGet module installed first.

    Install location (-Scope AllUsers) depends on the host that runs the script:
    - PowerShell 7: $env:ProgramFiles\PowerShell\Modules. Windows PowerShell 5.1
      does not search that folder, so a powershell.exe script cannot import the
      module, while later PowerShell 7 runs find it and report it already installed.
    - Windows PowerShell 5.1: $env:ProgramFiles\WindowsPowerShell\Modules, which
      both hosts search.
    Run the package under the host whose scripts will use PSWindowsUpdate.

    TLS 1.2: on the Windows PowerShell 5.1 Install-Module fallback only, the script
    adds Tls12 to [Net.ServicePointManager]::SecurityProtocol for the current process
    (a bitwise OR, so protocols already enabled stay enabled). Without it, a 5.1 host
    whose .NET Framework does not default to TLS 1.2 cannot reach PSGallery or
    bootstrap NuGet. Nothing is written to the registry, and the PSResourceGet path
    (and every PowerShell 7 run) leaves SecurityProtocol untouched. This goes away
    with the 5.1 fallback when #145 lands.

    Acceptance criteria deviations, both decided by the maintainer: the #132 criterion
    that the script sets no ServicePointManager was amended to allow the process-only
    TLS 1.2 above; and the Install-Module fallback on 5.1 (instead of
    Install-PSResource on every host) follows the precedent set in #125.
#>

function Get-ModuleInstaller {
    <#
    .SYNOPSIS
        Returns 'Install-PSResource' when PSResourceGet is available, 'Install-Module' on Windows PowerShell 5.1 without it, and throws otherwise.

    .PARAMETER Edition
        PowerShell edition to decide for. Defaults to the running one.
    #>
    param(
        [string]$Edition = $PSVersionTable.PSEdition
    )

    if (Get-Command -Name Install-PSResource -ErrorAction SilentlyContinue) {
        'Install-PSResource'
    }
    elseif ($Edition -eq 'Desktop' -and (Get-Command -Name Install-Module -ErrorAction SilentlyContinue)) {
        'Install-Module'
    }
    else {
        throw "Install-PSResource is not available in this $Edition edition PowerShell host. Install the Microsoft.PowerShell.PSResourceGet module or upgrade to PowerShell 7.4 or later."
    }
}

function Enable-Tls12ForProcess {
    <#
    .SYNOPSIS
        Adds TLS 1.2 to the protocols the current process may use, keeping those already enabled.

    .DESCRIPTION
        Process-only: nothing is written to the registry. Used only by the Windows
        PowerShell 5.1 Install-Module fallback. Remove it together with that fallback
        when #145 lands.
    #>
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

function Install-PSWindowsUpdateModule {
    <#
    .SYNOPSIS
        Installs PSWindowsUpdate for all users from PSGallery unless it is already installed.
    #>
    if (Get-Module -ListAvailable -Name PSWindowsUpdate) {
        Write-Output 'PSWindowsUpdate Module is Already Installed.'
        return
    }

    $Installer = Get-ModuleInstaller
    Write-Output "Installing PSWindowsUpdate with $Installer"
    if ($Installer -eq 'Install-PSResource') {
        Install-PSResource -Name PSWindowsUpdate -Repository PSGallery -Scope AllUsers -TrustRepository -AcceptLicense -Quiet -ErrorAction Stop
    }
    else {
        # Windows PowerShell 5.1 fallback only; removed with it when #145 lands.
        Enable-Tls12ForProcess
        Install-Module -Name PSWindowsUpdate -Repository PSGallery -Scope AllUsers -Force -Confirm:$false -ErrorAction Stop
    }
}

Install-PSWindowsUpdateModule
