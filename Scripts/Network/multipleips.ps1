<#
.SYNOPSIS
    Lists Active Directory computers whose DNS name resolves to the same IPv4 address as another computer.

.DESCRIPTION
    Gets every computer in the current domain with Get-ADComputer -Properties
    IPv4Address (the ActiveDirectory module resolves IPv4Address through DNS), finds
    the IPv4 addresses that occur more than once, and collects each computer whose
    address matches one of them.

    Outputs a Format-Table of Name and IPv4Address for those computers. When an
    address is shared by three or more computers, each of them is listed more than
    once. Changes nothing.

.EXAMPLE
    .\multipleips.ps1

    Shows the computers that share an IPv4 address in DNS.

.NOTES
    Requires the ActiveDirectory module (RSAT), a domain-joined computer and read
    access to the domain and DNS. Can take a long time in a large domain because each
    computer's address is looked up in DNS. No admin rights needed. Works in Windows
    PowerShell 5.1 and in PowerShell 7 on Windows with the ActiveDirectory module.
#>
#Import the Active Directory Module
Import-Module ActiveDirectory

#Define an empty array to store computers with duplicate IP address registrations in DNS
$duplicate_comp = @()

#Get all computers in the current Active Directory domain along with the IPv4 address
#The IPv4 address is not a property on the computer account so a DNS lookup is performed
#The list of computers is sorted based on IPv4 address and assigned to the variable $comp
$comp = Get-ADComputer -filter * -properties ipv4address | Sort-Object -property ipv4address

#For each computer object returned, assign just a sorted list of all
#of the IPv4 addresses for each computer to $sorted_ipv4
$sorted_ipv4 = $comp | ForEach-Object { $_.ipv4address } | Sort-Object

#For each computer object returned, assign just a sorted, unique list
#of all of the IPv4 addresses for each computer to $unique_ipv4
$unique_ipv4 = $comp | ForEach-Object { $_.ipv4address } | Sort-Object | Get-Unique

#compare $unique_ipv4 to $sorted_ipv4 and assign just the additional
#IPv4 addresses in $sorted_ipv4 to $duplicate_ipv4
$duplicate_ipv4 = Compare-Object -referenceobject $unique_ipv4 -differenceobject $sorted_ipv4 | ForEach-Object { $_.inputobject }

#For each instance in $duplicate_ipv4 and for each instance
#in $comp, compare $duplicate_ipv4 to $comp If they are equal, assign
#the computer object to array $duplicate_comp
foreach ($duplicate_inst in $duplicate_ipv4) {
    foreach ($comp_inst in $comp) {
        if (!($duplicate_inst.compareto($comp_inst.ipv4address))) {
            $duplicate_comp = $duplicate_comp + $comp_inst
        }
    }
}

#Pipe all of the duplicate computers to a formatted table
$duplicate_comp | Format-Table name, ipv4address -a