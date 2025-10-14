# Get the text from github
$url = "https://raw.githubusercontent.com/dotnet/docs/master/docs/framework/migration-guide/how-to-determine-which-versions-are-installed.md"
$md = Invoke-WebRequest $url -UseBasicParsing
$OFS = "`n"
# Replace the weird text in the tables, and the padding
# Then trim the | off the front and end of lines
$map = $md -split "`n" -replace " installed [^|]+" -replace "\s+\|" -replace "\|$" |
# Then we can build the table by looking for unique lines that start with ".NET Framework"
Select-String "^.NET" | Select-Object -Unique |
# And flip it so it's key = value
# And convert ".NET FRAMEWORK 4.5.2" to  [version]4.5.2
ForEach-Object { 
    [version]$v, [int]$k = $_ -replace "\.NET Framework " -split "\|"
    "    $k = [version]'$v'"
}

# And output the whole script
@"
`$Lookup = @{
    $map
}

# For extra effect we could get the Windows 10 OS version and build release id:
try {
    `$WinRelease, `$WinVer = Get-ItemPropertyValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" ReleaseId, CurrentMajorVersionNumber, CurrentMinorVersionNumber, CurrentBuildNumber, UBR
    `$WindowsVersion = "`$(`$WinVer -join '.') (`$WinRelease)"
}
catch {
    `$WindowsVersion = [System.Environment]::OSVersion.Version
}

Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP' -Recurse |
Get-ItemProperty -name Version, Release -EA 0 |
# For The One True framework (latest .NET 4x), change match to PSChildName -eq "Full":
Where-Object { `$_.PSChildName -match '^(?!S)\p{L}' } |
Select-Object @{name = ".NET Framework"; expression = { `$_.PSChildName } }, 
@{name = "Product"; expression = { `$Lookup[`$_.Release] } }, 
Version, Release,
# Some OPTIONAL extra output: PSComputerName and WindowsVersion
# The Computer name, so output from local machines will match remote machines:
@{ name = "PSComputerName"; expression = { `$Env:Computername } },
# The Windows Version (works on Windows 10, at least):
@{ name = "WindowsVersion"; expression = { `$WindowsVersion } }
"@