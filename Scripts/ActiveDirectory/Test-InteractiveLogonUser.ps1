function Test-InteractiveLogonUser {
    [cmdletbinding()]
    param (
        $Process = 'explorer'
    )
    if (Test-Process -ProcessName $Process) {
        Write-Verbose "Found explorer process(es). Assuming interactive user(s) logged in."
        Write-Output $true
    }
    else {
        Write-Verbose "No explorer processes found. Assuming no interactive user logged in."
        Write-Output $false
    }
}