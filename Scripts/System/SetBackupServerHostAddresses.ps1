$path = "$env:programdata\Cisco\Cisco AnyConnect Secure Mobility Client\Profile"
$NewHostAddressXML = '<HostAddress xmlns="http://schemas.xmlsoap.org/encoding/">vpn1.example.com</HostAddress><HostAddress xmlns="http://schemas.xmlsoap.org/encoding/">vpn2.example.com</HostAddress><HostAddress xmlns="http://schemas.xmlsoap.org/encoding/">vpn3.example.com</HostAddress><HostAddress xmlns="http://schemas.xmlsoap.org/encoding/">vpn4.example.com</HostAddress>'


if (Test-Path $path) {
    $targetFile = Get-ChildItem -Path $path -Filter *.xml -ErrorAction SilentlyContinue
    foreach ( $f in $targetFile ) {
        $content  = New-Object System.Xml.XmlDocument
        $content.Load($f.FullName)
        if $content.OuterXml -match 'Contoso' {
        $content.AnyConnectProfile.ClientInitialization.BackupServerList.InnerXML = $NewHostAddressXML
        $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
        $sw = New-Object System.IO.StreamWriter($f.FullName, $false, $utf8WithoutBom)
        $content.Save($sw)
        $sw.Close()
        }
        }
    }
