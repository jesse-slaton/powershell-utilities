<#
.SYNOPSIS
    Defines Import-WindowsErrorCode, which scrapes Windows error codes from MSDN pages.

.DESCRIPTION
    Defines the Import-WindowsErrorCode function and does nothing else: running the
    script without dot-sourcing it produces no output and leaves nothing defined. The
    function downloads MSDN system error code and WinINet error pages, writes their
    text to C:\Temp\TempData.txt, and outputs one object per error code (ErrorString,
    ExitCode, Hex Value, Description). See Get-Help Import-WindowsErrorCode -Full.

.EXAMPLE
    . .\Import-WindowsErrorCode.ps1
    $Codes = Import-WindowsErrorCode

    Dot-sources the script and stores the scraped list in $Codes.

.NOTES
    Requires Windows PowerShell 5.1: it uses the AllElements property of
    Invoke-WebRequest results, which PowerShell 7 does not provide. Needs network
    access to msdn.microsoft.com and an existing, writable C:\Temp folder. No admin
    rights needed otherwise.
#>


Function Import-WindowsErrorCode
{
<#
.SYNOPSIS
    Builds a list of Windows system and WinINet error codes by scraping MSDN pages.

.DESCRIPTION
    Downloads ten MSDN "System Error Codes" pages and the WinINet error page with
    Invoke-WebRequest, takes the text of each page's "mainsection" element, and cuts
    out the error list. The text is written to C:\Temp\TempData.txt (overwritten) and
    read back as lines, then parsed into objects with the properties ErrorString,
    ExitCode, Hex Value and Description, sorted by ExitCode. The objects are written
    to the output. The URLs are the old msdn.microsoft.com addresses; if those pages
    have moved or changed layout, the parsing does not find the expected text.

.EXAMPLE
    Import-WindowsErrorCode | Where-Object ExitCode -eq 5

    Scrapes the pages and shows any entries whose ExitCode is 5.

.EXAMPLE
    Import-WindowsErrorCode -Verbose | ConvertTo-Json | Set-Content .\ErrorCodes.json

    Saves the scraped list as JSON, showing progress messages.
#>
[cmdletbinding()]
Param()

    Begin
    {
        $SystemErrorURLs = @(
                         "https://msdn.microsoft.com/en-us/library/windows/desktop/ms681382(v=vs.85).aspx",
                         "https://msdn.microsoft.com/en-us/library/windows/desktop/ms681388(v=vs.85).aspx",
                         "https://msdn.microsoft.com/en-us/library/windows/desktop/ms681383(v=vs.85).aspx",
                         "https://msdn.microsoft.com/en-us/library/windows/desktop/ms681385(v=vs.85).aspx",
                         "https://msdn.microsoft.com/en-us/library/windows/desktop/ms681386(v=vs.85).aspx",
                         "https://msdn.microsoft.com/en-us/library/windows/desktop/ms681387(v=vs.85).aspx"
                         "https://msdn.microsoft.com/en-us/library/windows/desktop/ms681389(v=vs.85).aspx",
                         "https://msdn.microsoft.com/en-us/library/windows/desktop/ms681390(v=vs.85).aspx",
                         "https://msdn.microsoft.com/en-us/library/windows/desktop/ms681391(v=vs.85).aspx",
                         "https://msdn.microsoft.com/en-us/library/windows/desktop/ms681384(v=vs.85).aspx"
                        )
        $InternetErrorURL = "https://msdn.microsoft.com/en-us/library/windows/desktop/aa385465(v=vs.85).aspx"

        $ExtractedString_SystemErrorURLs = $ExtractedString_InternetErrorURL = $Output = @()
}
    Process
    {

        $ExtractedString_SystemErrorURLs = Foreach($URL in $SystemErrorURLs)
        {
            $Content = ((Invoke-WebRequest -uri $URL).allelements|?{$_.id -eq "mainsection"}).outertext
            (($Content -split "FORMAT_MESSAGE_FROM_SYSTEM flag.")[1] -split "Suggestions?")[0].trim()   
        }
        
        $Content_interneterrors =  ((Invoke-WebRequest -uri "https://msdn.microsoft.com/en-us/library/windows/desktop/aa385465(v=vs.85).aspx").allelements|?{$_.id -eq "mainsection"}).outerText
        $ExtractedString_InternetErrorURL = (($Content_interneterrors -split "The following errors are specific to the WinINet functions.")[1] -split "ERROR_INVALID_HANDLE")[0].trim()

        Write-Verbose "Creating temporary files and fetching the Content to parse"
        #This is aa single line String
        $ExtractedString_SystemErrorURLs + $ExtractedString_InternetErrorURL |Out-File C:\Temp\TempData.txt
        
        #Saving it in the file and then fetching the data using get content converts it to array of strings separated by EOL
        $Result = (Get-Content C:\Temp\TempData.txt).trim()
        
        #Parsing the exit codes and description
        $Output = for($i =0 ; $i -le ($Result.count-1) ;)
        {
            $ErrorString = ($Result[$i]).ToString()
            $i=$i+1
            $Exitcode = ($Result[$i]).trim().split(" ")[0]
            $hex = "0x$("{0:X0}" -f [int] $Exitcode)"
            $j=$i=$i+1
            
            While($Result[$i] -notlike "" -and $Result[$i] -notlike "ERROR_*" -and $Result[$i] -notlike "WAIT_*" -and $Result[$i] -notlike "ERROR_SETCOUNT_ON_BAD_LB*" -and $Result[$i] -notlike "RPC_*" -and $Result[$i] -notlike "EPT_*" -and $Result[$i] -notlike "SCHED_*" -and $Result[$i] -notlike "FRS_*" -and $Result[$i] -notlike "DNS_*" -and $Result[$i] -notlike "WSASERVICE_*" -and $Result[$i] -notlike "WSATYPE_*" -and $Result[$i] -notlike "WSA_*" -and $Result[$i] -notlike "WSATRY_*" -and $Result[$i] -notlike "WSAHOST_*" -and $Result[$i] -notlike "WSANO_*" -and $Result[$i] -notlike "WARNING_*" -and $Result[$i] -notlike "APPMODEL_*")
            {
                $i = $i+1
        }

            $str=''
            $Description = $Result[$j..($i-1)] | %{$str="$str$_";$str}

            If($Description -like $Result[$j-2])
            {
            $Description = $Result[$j]
            $i=$i+1
        }

            '' | select @{n='ErrorString';e={$ErrorString}}, @{n='ExitCode';e={[int]$Exitcode}}, @{n='Hex Value';e={$Hex}}, @{n='Description';e={$Description}} 
        } 

		Write-Verbose "All Exit code information has been extracted successfully"
		Write-Verbose "Sorting Information according to ExitCode numbers"

        $Output = $Output| ?{$_.ErrorString -ne 'ERROR_INTERNET_*'} |sort ExitCode

}
    End
    {
        $Output
    }  
}