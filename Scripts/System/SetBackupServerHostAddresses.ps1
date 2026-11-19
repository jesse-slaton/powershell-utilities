<#
.SYNOPSIS
    Replaces the backup server list in matching Cisco AnyConnect profiles.

.DESCRIPTION
    Looks at every .xml file in
    $env:ProgramData\Cisco\Cisco AnyConnect Secure Mobility Client\Profile. For each
    file whose XML text contains 'Contoso', replaces the contents of
    AnyConnectProfile/ClientInitialization/BackupServerList with four HostAddress
    entries (vpn1.example.com through vpn4.example.com) and saves the file as UTF-8
    without a BOM (the file must already contain a BackupServerList element). Files that do not contain 'Contoso' are not changed. Does nothing if
    the profile folder does not exist. Produces no output.

    The match text and host names are placeholders set in the script.

.EXAMPLE
    .\SetBackupServerHostAddresses.ps1

    Updates the backup server list in the matching AnyConnect profiles.

.NOTES
    Requires administrator rights to write under ProgramData\Cisco and the Cisco
    AnyConnect client profile folder. AnyConnect reads the profile on its next
    connection.
#>

$path = "$env:programdata\Cisco\Cisco AnyConnect Secure Mobility Client\Profile"
$NewHostAddressXML = '<HostAddress xmlns="http://schemas.xmlsoap.org/encoding/">vpn1.example.com</HostAddress><HostAddress xmlns="http://schemas.xmlsoap.org/encoding/">vpn2.example.com</HostAddress><HostAddress xmlns="http://schemas.xmlsoap.org/encoding/">vpn3.example.com</HostAddress><HostAddress xmlns="http://schemas.xmlsoap.org/encoding/">vpn4.example.com</HostAddress>'


if (Test-Path $path) {
    $targetFile = Get-ChildItem -Path $path -Filter *.xml -ErrorAction SilentlyContinue
    foreach ( $f in $targetFile ) {
        $content  = New-Object System.Xml.XmlDocument
        $content.Load($f.FullName)
        if ($content.OuterXml -match 'Contoso') {
        $content.AnyConnectProfile.ClientInitialization.BackupServerList.InnerXML = $NewHostAddressXML
        $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
        $sw = New-Object System.IO.StreamWriter($f.FullName, $false, $utf8WithoutBom)
        $content.Save($sw)
        $sw.Close()
        }
        }
    }
