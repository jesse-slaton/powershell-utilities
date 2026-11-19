<#
.SYNOPSIS
    Unfinished sensor meant to print a process tree; as written, its filter does not work.

.DESCRIPTION
    Defines Show-ProcessTree and calls it with -ProcessName 'Firefox.exe'. The intended
    output is each top-level process name followed by its child processes, indented, as
    "|--<Name>, <ProcessId>" lines, built from Win32_Process.

    As written, the function ignores ProcessName and ProcessID (the code that used them
    is commented out). It assigns to $pid, which is PowerShell's read-only automatic
    variable, and uses the filter { Get-Process -ID $pid._parentprocessid } to choose
    the top-level processes. That filter does not select processes by their parent, so
    the output is not a usable process tree.

.EXAMPLE
    .\Show-ProcessTree-Sensor.ps1

    Runs the function as written; see the description for why the result is not usable.

.NOTES
    Uses the CIM cmdlets; runs on Windows PowerShell 5.1 and PowerShell 7. No admin
    rights needed to list processes.
#>


Function Show-ProcessTree {
    Param(
        $ProcessName,
        $ProcessID
    )
    # if ($null -ne $ProcessName) {
    #     $filter = (Get-Process -Name $($ProcessName -replace "\..+")).ParentProcessId
    # }
    # if ($null -ne $ProcessID) {
    #     $filter = (Get-Process -ID $ProcessID).ParentProcessId
    # }    
    $pid = "$35824"
    $filter = { Get-Process -ID $pid._parentprocessid }
    Function Get-ProcessChildren($P, $Depth = 1) {
        $procs | Where-Object { $_.ParentProcessId -eq $p.ProcessID -and $_.ParentProcessId -ne 0 } | ForEach-Object {
            "{0}|--{1}, {2}" -f (" " * 3 * $Depth), $_.Name, $_.ProcessID
            Get-ProcessChildren $_ (++$Depth)
            $Depth--
        }
    }
    if ($null -eq $filter) {
        $filter = { -not (Get-Process -Id $_.ParentProcessId -ErrorAction SilentlyContinue) -or $_.ParentProcessId -eq 0 }
    }
    $procs = Get-CimInstance -ClassName Win32_Process

    $top = $procs | Where-Object $filter | Sort-Object ProcessID
    foreach ($p in $top) {
        $p.Name
        Get-ProcessChildren $p
    }
}
Show-ProcessTree -ProcessName 'Firefox.exe'