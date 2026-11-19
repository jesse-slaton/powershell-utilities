<#
.SYNOPSIS
    Runs the Tableau Desktop uninstaller passed as the first argument, silently.

.DESCRIPTION
    URL-decodes the first positional argument ($args[0]) with
    [System.Uri]::UnescapeDataString, removes ' /modify' from it, and uses the result as
    the uninstaller path. It starts that file with the arguments '/uninstall /quiet' in
    a hidden window and waits for it to finish (start errors are suppressed).

    The switch that checks the exit code uses the condition {0,1605,3010}, a script
    block that always evaluates as true, so "Removed Tableau Desktop" is written with
    Write-Host for every exit code, and the default branch ($Host.SetShouldExit(1)) is
    never reached.

    The script has no param() block; the argument is read from $args.

.EXAMPLE
    .\RemoveTableauDesktop.ps1 '<UninstallString>'

    Runs the given uninstaller with '/uninstall /quiet' after removing a trailing
    ' /modify'.

.NOTES
    Requires administrator rights. The argument must be only the uninstaller path,
    optionally followed by ' /modify'; any quotes or other arguments in it become part
    of the path passed to Start-Process.
#>
[String]$ParamString  = [System.Uri]::UnescapeDataString($args[0])
$UninstallString = $ParamString.Replace(' /modify','')
$Arguments = "/uninstall /quiet"

$Uninstaller = start-process -FilePath $UninstallString -ArgumentList $Arguments -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue -PassThru
switch ($Uninstaller.ExitCode) {
    {0,1605,3010} {
        write-host "Removed Tableau Desktop"
    }
    default {
        $Host.SetShouldExit(1)
    }
}