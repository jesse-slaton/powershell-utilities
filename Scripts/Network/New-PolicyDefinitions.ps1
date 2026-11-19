#requires -Version 3
<#
.SYNOPSIS
    Writes policy.json metadata files into a local clone of the Secure-Host-Baseline repository.

.DESCRIPTION
    Changes the current location to a hard-coded base path,
    $env:USERPROFILE\Documents\GitHub\Secure-Host-Baseline, and leaves the session
    there after the script ends.

    Then writes 16 policy.json files (ASCII, overwriting existing ones) under
    "<Area>\Group Policy Objects\..." folders for ActivClient, Adobe Reader, AppLocker
    (Audit and Enforced), BitLocker, Certificates, Chrome, EMET, Internet Explorer
    (Computer and User), Office 2013, Office 2016 (Computer and User), Windows
    (Computer and User) and Windows Firewall. Each file is a JSON object with
    PolicyName, PolicyScopes, PolicyTypes, PolicyModes, PolicyTemplatePath,
    PolicyTemplateType and PolicyTemplateVersion. OS templates use version
    10.0.14393.0 (Windows 10 1607). Produces no console output.

.EXAMPLE
    .\New-PolicyDefinitions.ps1

    Regenerates the policy.json files in the Secure-Host-Baseline clone under the
    current user's Documents\GitHub folder.

.NOTES
    Requires a clone of the Secure-Host-Baseline repository at the hard-coded path, with
    the target folders already present (Out-File does not create folders). Runs under
    Set-StrictMode -Version 3. No admin rights needed. PowerShell 3.0 or later.
#>
Set-StrictMode -Version 3

# todo: turn into functions

# todo: removed hardcoded path
$basePath = "$env:USERPROFILE\Documents\GitHub\Secure-Host-Baseline"

# Windows 10 1607 OS Group Policy Templates 
# taken from https://www.microsoft.com/en-us/download/details.aspx?id=53430 (Version 2.0 released on 01/08/2017)
# Note that there are some differences between Version 2.0 and what is in the PolicyDefinitions folder on a Windows 10 Enterprise 1607 14393.693 system as of 01/18/2017
$osVersion = '10.0.14393.0'

Set-Location -Path $basePath

$policy = [pscustomobject]@{
    'PolicyName' = 'ActivClient';
    'PolicyScopes' = [string[]]@('Computer');
    'PolicyTypes' = [string[]]@('Domain','Local');
    'PolicyModes' = [string[]]@('Audit','Enforced');
    'PolicyTemplatePath' = '.\..\..\';
    'PolicyTemplateType' = 'Application';
    'PolicyTemplateVersion' = '7.1.0.157';
}

$policyPath = "$basePath\ActivClient\Group Policy Objects\Computer"
$policy | ConvertTo-Json | Out-File -FilePath "$policyPath\policy.json" -Encoding ASCII -Force

$policy = [pscustomobject]@{
    'PolicyName' = 'Adobe Reader';
    'PolicyScopes' = [string[]]@('Computer');
    'PolicyTypes' = [string[]]@('Domain','Local');
    'PolicyModes' = [string[]]@('Audit','Enforced');
    'PolicyTemplatePath' = '.\..\..\';
    'PolicyTemplateType' = 'Application';
    'PolicyTemplateVersion' = '15.23.0.0';
}

$policyPath = "$basePath\Adobe Reader\Group Policy Objects\Computer"
$policy | ConvertTo-Json | Out-File -FilePath "$policyPath\policy.json" -Encoding ASCII -Force


$policy = [pscustomobject]@{
    'PolicyName' = 'AppLocker';
    'PolicyScopes' = [string[]]@('Computer');
    'PolicyTypes' = [string[]]@('Domain','Local');
    'PolicyModes' = [string[]]@('Audit');
    'PolicyTemplatePath' = '.\..\..\..\..\Windows\';
    'PolicyTemplateType' = 'OS';
    'PolicyTemplateVersion' = $osVersion;
}

$policyPath = "$basePath\AppLocker\Group Policy Objects\Computer\Audit"
$policy | ConvertTo-Json | Out-File -FilePath "$policyPath\policy.json" -Encoding ASCII -Force


$policy = [pscustomobject]@{
    'PolicyName' = 'AppLocker';
    'PolicyScopes' = [string[]]@('Computer');
    'PolicyTypes' = [string[]]@('Domain','Local');
    'PolicyModes' = [string[]]@('Enforced');
    'PolicyTemplatePath' = '.\..\..\..\..\Windows\';
    'PolicyTemplateType' = 'OS';
    'PolicyTemplateVersion' = $osVersion;
}

$policyPath = "$basePath\AppLocker\Group Policy Objects\Computer\Enforced"
$policy | ConvertTo-Json | Out-File -FilePath "$policyPath\policy.json" -Encoding ASCII -Force


$policy = [pscustomobject]@{
    'PolicyName' = 'BitLocker';
    'PolicyScopes' = [string[]]@('Computer');
    'PolicyTypes' = [string[]]@('Domain','Local');
    'PolicyModes' = [string[]]@('Audit','Enforced');
    'PolicyTemplatePath' = '.\..\..\..\Windows\';
    'PolicyTemplateType' = 'OS';
    'PolicyTemplateVersion' = $osVersion;
}

$policyPath = "$basePath\BitLocker\Group Policy Objects\Computer"
$policy | ConvertTo-Json | Out-File -FilePath "$policyPath\policy.json" -Encoding ASCII -Force

$policy = [pscustomobject]@{
    'PolicyName' = 'Certificates'
    'PolicyScopes' = [string[]]@('Computer');
    'PolicyTypes' = [string[]]@('Domain', 'Local');
    'PolicyModes' = [string[]]@('Audit','Enforced');
    'PolicyTemplatePath' = '.\..\..\..\Windows';
    'PolicyTemplateType' = 'OS';
    'PolicyTemplateVersion' = $osVersion;
}

$policyPath = "$basePath\Certificates\Group Policy Objects\Computer"
$policy | ConvertTo-Json | Out-File -FilePath "$policyPath\policy.json" -Encoding ASCII -Force

$policy = [pscustomobject]@{
    'PolicyName' = 'Chrome';
    'PolicyScopes' = [string[]]@('Computer');
    'PolicyTypes' = [string[]]@('Domain','Local');
    'PolicyModes' = [string[]]@('Audit','Enforced');
    'PolicyTemplatePath' = '.\..\..\';
    'PolicyTemplateType' = 'Application';
    'PolicyTemplateVersion' = '55.0.2883.87';
}

$policyPath = "$basePath\Chrome\Group Policy Objects\Computer"
$policy | ConvertTo-Json | Out-File -FilePath "$policyPath\policy.json" -Encoding ASCII -Force


$policy = [pscustomobject]@{
    'PolicyName' = 'EMET';
    'PolicyScopes' = [string[]]@('Computer');
    'PolicyTypes' = [string[]]@('Domain','Local');
    'PolicyModes' = [string[]]@('Audit','Enforced');
    'PolicyTemplatePath' = '.\..\..\';
    'PolicyTemplateType' = 'Application';
    'PolicyTemplateVersion' = '5.51.0.0';
}

$policyPath = "$basePath\EMET\Group Policy Objects\Computer"
$policy | ConvertTo-Json | Out-File -FilePath "$policyPath\policy.json" -Encoding ASCII -Force


$policy = [pscustomobject]@{
    'PolicyName' = 'Internet Explorer';
    'PolicyScopes' = [string[]]@('Computer');
    'PolicyTypes' = [string[]]@('Domain','Local');
    'PolicyModes' = [string[]]@('Audit','Enforced');
    'PolicyTemplatePath' = '.\..\..\..\Windows';
    'PolicyTemplateType' = 'OS';
    'PolicyTemplateVersion' = $osVersion;
}

$policyPath = "$basePath\Internet Explorer\Group Policy Objects\Computer"
$policy | ConvertTo-Json | Out-File -FilePath "$policyPath\policy.json" -Encoding ASCII -Force


$policy = [pscustomobject]@{
    'PolicyName' = 'Internet Explorer'
    'PolicyScopes' = [string[]]@('User');
    'PolicyTypes' = [string[]]@('Domain','Local');
    'PolicyModes' = [string[]]@('Audit','Enforced');
    'PolicyTemplatePath' = '.\..\..\..\Windows';
    'PolicyTemplateType' = 'OS';
    'PolicyTemplateVersion' = $osVersion;
}

$policyPath = "$basePath\Internet Explorer\Group Policy Objects\User"
$policy | ConvertTo-Json | Out-File -FilePath "$policyPath\policy.json" -Encoding ASCII -Force


$policy = [pscustomobject]@{
    'PolicyName' = 'Office 2013'
    'PolicyScopes' = [string[]]@('Computer','User');
    'PolicyTypes' = [string[]]@('Domain','Local');
    'PolicyModes' = [string[]]@('Audit','Enforced');
    'PolicyTemplatePath' = '.\..\';
    'PolicyTemplateType' = 'Application';
    'PolicyTemplateVersion' = '15.0.0.0';
}

$policyPath = "$basePath\Office\Office 2013\Group Policy Objects"
$policy | ConvertTo-Json | Out-File -FilePath "$policyPath\policy.json" -Encoding ASCII -Force

$policy = [pscustomobject]@{
    'PolicyName' = 'Office 2016'
    'PolicyScopes' = [string[]]@('Computer');
    'PolicyTypes' = [string[]]@('Domain','Local');
    'PolicyModes' = [string[]]@('Audit','Enforced');
    'PolicyTemplatePath' = '.\..\..\';
    'PolicyTemplateType' = 'Application';
    'PolicyTemplateVersion' = '16.0.0.0';
}

$policyPath = "$basePath\Office\Office 2016\Group Policy Objects\Computer"
$policy | ConvertTo-Json | Out-File -FilePath "$policyPath\policy.json" -Encoding ASCII -Force

$policy = [pscustomobject]@{
    'PolicyName' = 'Office 2016'
    'PolicyScopes' = [string[]]@('User');
    'PolicyTypes' = [string[]]@('Domain','Local');
    'PolicyModes' = [string[]]@('Audit','Enforced');
    'PolicyTemplatePath' = '.\..\..\';
    'PolicyTemplateType' = 'Application';
    'PolicyTemplateVersion' = '16.0.0.0';
}

$policyPath = "$basePath\Office\Office 2016\Group Policy Objects\User"
$policy | ConvertTo-Json | Out-File -FilePath "$policyPath\policy.json" -Encoding ASCII -Force


$policy = [pscustomobject]@{
    'PolicyName' = 'Windows'
    'PolicyScopes' = [string[]]@('Computer');
    'PolicyTypes' = [string[]]@('Domain','Local');
    'PolicyModes' = [string[]]@('Audit','Enforced');
    'PolicyTemplatePath' = '.\..\..\';
    'PolicyTemplateType' = 'OS';
    'PolicyTemplateVersion' = $osVersion;
}

$policyPath = "$basePath\Windows\Group Policy Objects\Computer"
$policy | ConvertTo-Json | Out-File -FilePath "$policyPath\policy.json" -Encoding ASCII -Force


$policy = [pscustomobject]@{
    'PolicyName' = 'Windows'
    'PolicyScopes' = [string[]]@('User');
    'PolicyTypes' = [string[]]@('Domain','Local');
    'PolicyModes' = [string[]]@('Audit','Enforced');
    'PolicyTemplatePath' = '.\..\..\';
    'PolicyTemplateType' = 'OS';
    'PolicyTemplateVersion' = $osVersion;
}

$policyPath = "$basePath\Windows\Group Policy Objects\User"
$policy | ConvertTo-Json | Out-File -FilePath "$policyPath\policy.json" -Encoding ASCII -Force


$policy = [pscustomobject]@{
    'PolicyName' = 'Windows Firewall'
    'PolicyScopes' = [string[]]@('Computer');
    'PolicyTypes' = [string[]]@('Domain','Local');
    'PolicyModes' = [string[]]@('Audit','Enforced');
    'PolicyTemplatePath' = '.\..\..\..\Windows';
    'PolicyTemplateType' = 'OS';
    'PolicyTemplateVersion' = $osVersion;
}

$policyPath = "$basePath\Windows Firewall\Group Policy Objects\Computer"
$policy | ConvertTo-Json | Out-File -FilePath "$policyPath\policy.json" -Encoding ASCII -Force


