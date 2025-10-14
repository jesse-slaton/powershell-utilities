<# 
    PURPOSE: This PowerShell script generates an Office Configuration file to include additional Office products 
    and installs Office 365 ProPlus with those products using the Office Deployment Tool.
#>

# Defines a function to retrieve the Office configuration data from the Windows Registry.
function Get-OfficeConfiguration {
  param (
    [string]$Path = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration',
    [string]$Value
  )
  Write-Host -Message "Getting Office Configuration $Value"
  
  # Retrieve the registry value data using the Get-ItemProperty cmdlet and store it in the $RegistryData variable.
  $RegistryData = (Get-ItemProperty -Path $Path -Name $Value).$Value
  
  # If the registry value data is not null, write a message to the console with the data and return it.
  if ($RegistryData) {
    Write-Host -Message "Office Configuration for $Value is $RegistryData"
    return $RegistryData
  }
  # If the registry value data is null, write a warning message to the console.
  else {
    Write-Host -Message "Unable to find office configuration data for $Value" -Level Warn
  }
}

# Defines the Windows Registry path to the Office Click-to-Run Configuration key.
$OfficeRegistryPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'

# Defines the XML content for the Office Configuration file.
$OfficeConfiguration = @"
<Configuration>
  <Add Channel="Current" OfficeClientEdition="64" ForceUpgrade="TRUE" MigrateArch="TRUE">
    <Product ID="O365ProPlusRetail">
      <Language ID="MatchOS" />
      <ExcludeApp ID="Groove" />
      <ExcludeApp ID="Lync" />
      <ForceAppShutdown>true</ForceAppShutdown>
    </Product>
  </Add>
  <Updates Enabled="TRUE" />
  <RemoveMSI />
  <AppSettings>
    <Setup Name="Company" Value="City of Coronado" />
  </AppSettings>
  <Display Level="Full" AcceptEULA="TRUE" />
</Configuration>
"@

# Loads the XML content from the variable into an XML document object.
[xml]$OfficeConfigurationXml = $OfficeConfiguration

# Retrieves a list of installed Office products by reading the 'ProductReleaseIds' registry value.
# Excludes Office 365 itself.
$ProductReleaseIds = (Get-OfficeConfiguration -Path $OfficeRegistryPath -Value 'ProductReleaseIds').split(',') | Where-Object { $_ -Notmatch 'O365' }

# Loops through each installed Office product, appends the XML for the new product to the Office Configuration file, and saves the modified XML to a variable.
foreach ($ProductID in $ProductReleaseIds) {
  $addElement = $OfficeConfigurationXml.SelectSingleNode('//Configuration/Add')
  
  # Creates a new <product> element.
  $newProduct = $OfficeConfigurationXml.CreateElement('Product')
  # Sets the attributes or child elements for the new <product> element as needed.
  $newProduct.SetAttribute('ID', $ProductID)
  
  # Sets the product language ID to match the operating system.
  $LanguageID = $OfficeConfigurationXml.CreateElement('Language')
  $LanguageID.SetAttribute('ID', 'MatchOS')
  $newProduct.AppendChild($LanguageID) # Appends the Language
    
  # Exclude Lync and Groove (Old OneDrive for Business)
  $ExcludedApp = $OfficeConfigurationXml.CreateElement('ExcludeApp')
  $ExcludedApp.SetAttribute('ID', 'Groove')
  $newProduct.AppendChild($ExcludedApp) # Append ExcludedApp element to newProduct
  $ExcludedApp2 = $OfficeConfigurationXml.CreateElement('ExcludeApp')
  $ExcludedApp2.SetAttribute('ID', 'Lync')
  $newProduct.AppendChild($ExcludedApp2) # Append ExcludedApp2 element to newProduct

  # Force Office Apps to Shutdown
  $forceAppShutdown = $OfficeConfigurationXml.CreateElement("ForceAppShutdown")
  $forceAppShutdown.InnerText = "true"
  $newProduct.AppendChild($forceAppShutdown) # Append forceAppShutdown element to newProduct
    
  # Append the new <product> element as a child of the <Add> element
  $addElement.AppendChild($newProduct)
}

# Use XmlTextWriter to format the XML output with indentation and line breaks
$settings = New-Object System.Xml.XmlWriterSettings
$settings.Indent = $true
$settings.OmitXmlDeclaration = $true
$sw = New-Object System.IO.StringWriter
$writer = [System.Xml.XmlTextWriter]::Create($sw, $settings)
$OfficeConfigurationXml.WriteTo($writer)
$writer.Flush()
$writer.Close()
$modifiedXml = $sw.ToString()

# Save the modified XML content to a configuration.xml file
Set-Content -Path "configuration.xml" -Value $modifiedXml

# Run the Office Deployment Tool to install Office 365 ProPlus with any additional Products
$configPath = ".\configuration.xml"
$setupPath = ".\setup.exe"
$ODT = Start-Process -FilePath $setupPath -ArgumentList "/configure", $configPath -Wait -PassThru
$exitCode = $ODT.ExitCode

switch ($exitCode) {
  0 { Write-Output "Success: Office Click-to-Run update completed successfully." }
  1601 { Write-Warning "Warning: Update already in progress. Please try again later." }
  1704 { Write-Warning "Warning: An Office installation is currently suspended. Please resume the installation and try again." }
  3010 { Write-Warning "Warning: Office Click-to-Run update requires a reboot to complete." }
  default { Write-Error "Error: Office Click-to-Run update failed with exit code $($exitCode)." }
}
