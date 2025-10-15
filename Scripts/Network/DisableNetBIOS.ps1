$nics = Get-WmiObject -Query 'SELECT * from Win32_NetworkAdapterConfiguration WHERE IPEnabled = TRUE'
ForEach ($nic in $nics) {
    $nic.SetTcpipNetbios(2)
}