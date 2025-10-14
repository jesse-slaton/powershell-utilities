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

$URI = "https://contoso.service-now.com/api/now/table/sys_user"
Get-UserCredentials


$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username, ([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))))))

$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add('Authorization',('Basic {0}' -f $base64AuthInfo))
$headers.Add('Accept','application/json')
$headers.Add('Content-Type','application/json')

# Specify endpoint uri
# Set above in environment logic

# Specify HTTP method
$method = "get"

$Users = Invoke-RestMethod -Headers $headers -Method $method -Uri $URI 