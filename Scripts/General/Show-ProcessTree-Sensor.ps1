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
    $procs = Get-WmiObject Win32_Process

    $top = $procs | Where-Object $filter | Sort-Object ProcessID
    foreach ($p in $top) {
        $p.Name
        Get-ProcessChildren $p
    }
}
Show-ProcessTree -ProcessName 'Firefox.exe'