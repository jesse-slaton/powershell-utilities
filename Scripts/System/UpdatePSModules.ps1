<#
.SYNOPSIS
    Defines Update-Modules, a function that updates installed PowerShell Gallery modules and removes older versions.

.DESCRIPTION
    Running the script only defines the Update-Modules function; dot-source it
    (. .\UpdatePSModules.ps1) to make the function available, then call it.

    Update-Modules returns with a warning unless the session is elevated. It lists the
    modules installed with Install-Module (Get-InstalledModule) that match -Name. For
    each one it compares the installed version with Find-Module and, when the gallery
    version is newer, runs Update-Module -Scope AllUsers -AcceptLicense -Force. It then
    uninstalls every installed version except the most recently published one. At the
    end it lists the modules whose version changed. Progress is written with Write-Host.

    Function parameters:
    -Name <string>       Module name or wildcard to process. Default '*'.
    -AllowPrerelease     Allow prerelease versions when updating.
    -WhatIf              Passed to Update-Module and Uninstall-Module so nothing is
                         changed; the version check against the gallery still runs.

.EXAMPLE
    . .\UpdatePSModules.ps1
    Update-Modules

    Defines the function, then updates all installed gallery modules.

.EXAMPLE
    . .\UpdatePSModules.ps1
    Update-Modules -Name 'Az.*' -WhatIf

    Shows what would be updated and uninstalled for the Az modules without changing them.

.NOTES
    Update-Modules requires administrator rights, PowerShellGet (Get-InstalledModule,
    Find-Module, Update-Module) and internet access to the PowerShell Gallery. Only
    modules installed with Install-Module are processed.
#>


function Update-Modules {
	param (
		[switch]$AllowPrerelease,
		[string]$Name = '*',
		[switch]$WhatIf
	)

	# Test admin privileges without using -Requires RunAsAdministrator,
	# which causes a nasty error message, if trying to load the function within a PS profile but without admin privileges
	if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
		Write-Warning ("Function {0} needs admin privileges. Break now." -f $MyInvocation.MyCommand)
		return
	}

	# Get all installed modules
	Write-Host ("Retrieving all installed modules ...") -ForegroundColor Green
	$CurrentModules = Get-InstalledModule -Name $Name -ErrorAction SilentlyContinue | Select-Object Name, Version | Sort-Object Name

	if (-not $CurrentModules) {
		Write-Host ("No modules found.") -ForegroundColor Gray
		return
	}
	else {
		$ModulesCount = $CurrentModules.Name.Count
		$DigitsLength = $ModulesCount.ToString().Length
		Write-Host ("{0} modules found." -f $ModulesCount) -ForegroundColor Gray
	}

	# Show status of AllowPrerelease Switch
	''
	if ($AllowPrerelease) {
		Write-Host ("Updating installed modules to the latest PreRelease version ...") -ForegroundColor Green
	}
	else {
		Write-Host ("Updating installed modules to the latest Production version ...") -ForegroundColor Green
	}

	# Loop through the installed modules and update them if a newer version is available
	$i = 0
	foreach ($Module in $CurrentModules) {
		$i++
		$Counter = ("[{0,$DigitsLength}/{1,$DigitsLength}]" -f $i, $ModulesCount)
		$CounterLength = $Counter.Length
		Write-Host ('{0} Checking for updated version of module {1} ...' -f $Counter, $Module.Name) -ForegroundColor Green
		try {
			$latest = Find-Module $Module.Name -ErrorAction Stop
			if ([version]$Module.Version -lt [version]$latest.version) {
				Update-Module -Name $Module.Name -AllowPrerelease:$AllowPrerelease -AcceptLicense -Scope:AllUsers -Force:$True -ErrorAction Stop -WhatIf:$WhatIf.IsPresent
			}
		}
		catch {
			Write-Host ("{0$CounterLength} Error updating module {1}!" -f ' ', $Module.Name) -ForegroundColor Red
		}

		# Retrieve newest version number and remove old(er) version(s) if any
		$AllVersions = Get-InstalledModule -Name $Module.Name -AllVersions | Sort-Object PublishedDate -Descending
		$MostRecentVersion = $AllVersions[0].Version
		if ($AllVersions.Count -gt 1 ) {
			Foreach ($Version in $AllVersions) {
				if ($Version.Version -ne $MostRecentVersion) {
					try {
						Write-Host ("{0,$CounterLength} Uninstalling previous version {1} of module {2} ..." -f ' ', $Version.Version, $Module.Name) -ForegroundColor Gray
						Uninstall-Module -Name $Module.Name -RequiredVersion $Version.Version -Force:$True -ErrorAction Stop -AllowPrerelease -WhatIf:$WhatIf.IsPresent
					}
					catch {
						Write-Warning ("{0,$CounterLength} Error uninstalling previous version {1} of module {2}!" -f ' ', $Version.Version, $Module.Name)
					}
				}
			}
		}
	}

	# Get the new module versions for comparing them to to previous one if updated
	$NewModules = Get-InstalledModule -Name $Name | Select-Object Name, Version | Sort-Object Name
	if ($NewModules) {
		''
		Write-Host ("List of updated modules:") -ForegroundColor Green
		$NoUpdatesFound = $true
		foreach ($Module in $NewModules) {
			$CurrentVersion = $CurrentModules | Where-Object Name -EQ $Module.Name
			if ($CurrentVersion.Version -notlike $Module.Version) {
				$NoUpdatesFound = $false
				Write-Host ("- Updated module {0} from version {1} to {2}" -f $Module.Name, $CurrentVersion.Version, $Module.Version) -ForegroundColor Green
			}
		}

		if ($NoUpdatesFound) {
			Write-Host ("No modules were updated.") -ForegroundColor Gray
		}
	}
}