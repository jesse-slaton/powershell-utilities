#Requires -Modules @{ ModuleName = 'ServiceNow'; ModuleVersion = '5.0.0' }
<#
.SYNOPSIS
    Prompts for domain credentials, checks them against Active Directory, and reads every
    ServiceNow user record into $Users.

.DESCRIPTION
    Get-UserCredentials prompts for domain\username and password and binds to the
    current domain over LDAP with them. On a wrong password it warns, counts the attempt
    and asks again; after three failures it also waits 30 seconds before each further
    prompt. Once the bind succeeds, the script opens a ServiceNow session with the
    username (without the domain) and the password, using New-ServiceNowSession from the
    ServiceNow module, and reads every record of the sys_user table with
    Get-ServiceNowRecord into $Users. Nothing is written to the pipeline, and despite its
    name the script creates no incidents. Read-only.

.PARAMETER ServiceNowUrl
    Host name of the ServiceNow instance, without https:// (for example
    <instance>.service-now.com). Defaults to a placeholder that must be replaced.

.EXAMPLE
    .\Create-BulkSNIncidents.ps1 -ServiceNowUrl <instance>.service-now.com

    Prompts for credentials and reads the sys_user table of that instance.

.EXAMPLE
    . .\Create-BulkSNIncidents.ps1 -ServiceNowUrl <instance>.service-now.com
    $Users.Count

    Dot-sources the script so that $Users stays in the session, then counts the records.

.NOTES
    Requires the ServiceNow module 5.0.0 or later (Install-Module ServiceNow), which
    replaced the copy of v1.1.0 removed in #39. Needs network access to the domain and to
    the ServiceNow instance, and an account that ServiceNow accepts for basic
    authentication with read access to sys_user.
#>
param(
    # ServiceNow instance host name, without https://.
    [string]$ServiceNowUrl = 'contoso.service-now.com'
)

function Get-UserCredentials{
    $counter = 0
    $more = $true
    while($more){
        if($counter -ge 3){
            Write-Warning -Message ('Take a deep breath and perhaps a break.  You have entered your password {0} times incorrectly' -f $counter)
            Write-Warning -Message ('Please wait until {0} to try again to avoid risking locking yourself out.' -f $((Get-Date).AddMinutes(+15).ToShortTimeString()))
            Start-Sleep -Seconds 30
        }

        # Collect the username and password and store in credential object.
        $Script:userName = Read-Host -Prompt 'Please enter your domain\username'
        $Script:password = Read-Host -AsSecureString -Prompt 'Please enter your password'
         
        try{
            $credential = New-Object System.Management.Automation.PSCredential $userName,$password

            # Build the current domain
            $currentDomain = 'LDAP://{0}' -f $credential.GetNetworkCredential().Domain

            # Get the user\password. The GetNetworkCredential only works for the passwrod because the current user
            # is the one who entered it.  Shouldn't be accessible to anything\one else.
            $Script:userName = $credential.GetNetworkCredential().UserName

            $password2 = $credential.GetNetworkCredential().Password

        }
        catch{
            Write-Warning -Message ('There was a problem with what you entered: {0}' -f $_.exception.message)
            continue
        }

        # Do a quick query against the domain to authenticate the user.
        $dom = New-Object System.DirectoryServices.DirectoryEntry($currentDomain,$userName,$password2)
        # If we get a result back with a name property then we're good to go and we can store the credential.
        if($dom.name){
            Write-Output $credential
            $more = $false
            Remove-Variable password2 -Force
        }
        else{
            $counter++

            Write-Warning -Message ('The password you entered for {0} was incorrect.  Attempts {1}. Please try again.' -f $userName,$counter)
        }
    }
} #end Function Get-UserCredentials

Get-UserCredentials | Out-Null

# ServiceNow gets the username without the domain, as the former hand-built Basic header did.
$ServiceNowCredential = New-Object System.Management.Automation.PSCredential $Script:userName, $Script:password
New-ServiceNowSession -Url $ServiceNowUrl -Credential $ServiceNowCredential

$Users = Get-ServiceNowRecord -Table sys_user
