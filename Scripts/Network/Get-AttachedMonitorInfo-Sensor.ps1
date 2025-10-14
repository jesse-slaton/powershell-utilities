#Requires -Version 3.0
<#

.SYNOPSIS
This PowerShell function gets information about the monitors attached to any computer.
It uses EDID information provided by WMI. If this value is not specified it pulls the
monitors of the computer that the script is being run on.

.DESCRIPTION
The function begins by looping through each computer specified. For each computer it
gets a list of monitors. It then gets all of the necessary data from each monitor object
and converts and cleans the data and places it in a custom PSObject. It then adds the
data to an array. At the end the array is displayed.

.PARAMETER ComputerName
Use this to specify the computer(s) which you'd like to retrieve information about
monitors from.

.EXAMPLE
PS C:/> Get-AttachedMonitorInfo.ps1

Manufacturer  : HP
Model         : HP E243i
SerialNumber  : CNK7290KPM
Week          : 29
Year          : 2017
Connection    : Displayport
Size          : 24
MaxResolution : 1920 x 1200

#>

[CmdletBinding()]
PARAM (
[Parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
[String[]]$ComputerName = $env:ComputerName
)

#List of Manufacture Codes that could be pulled from WMI and their respective full names.
$DictionaryDir = 'C:\DesktopSupportTools\Dictionaries'
$EDID_Manufacturers = $DictionaryDir + '\edid_manufacturers.csv'
IF (!(Test-Path $EDID_Manufacturers)) {}
Import-CSV $EDID_Manufacturers -ErrorAction Stop | foreach { $ManufacturerHash = @{}} { $ManufacturerHash[$_."#Fields:ID"] = $_.Manufacturer }


#List of friendly names for display input types.
$InputTypeHash = @{
    "-2" = "Uninitialized";
    "-1" = "Other";
    "0" = "VGA";
    "1" = "SVideo";
    "2" = "Composite";
    "3" = "Component";
    "4" = "DVI";
    "5" = "HDMI";
    "6" = "Internal";
    "8" = "D-Jpn";
    "9" = "SDI";
    "10" = "Displayport";
    "11" = "Internal";
    "12" = "UDI";
    "13" = "Internal";
    "14" = "SDTV_Dongle";
    "15" = "Wireless";
    "2147483648" = "Internal";
}
#List of names for display input types from WMI.
$RawInputTypeHash = @{
    "-2" = "D3DKMDT_VOT_UNINITIALIZED";
    "-1" = "D3DKMDT_VOT_OTHER";
    "0" = "D3DKMDT_VOT_HD15 (VGA)";
    "1" = "D3DKMDT_VOT_SVIDEO";
    "2" = "D3DKMDT_VOT_COMPOSITE_VIDEO";
    "3" = "D3DKMDT_VOT_COMPONENT_VIDEO";
    "4" = "D3DKMDT_VOT_DVI";
    "5" = "D3DKMDT_VOT_HDMI";
    "6" = "D3DKMDT_VOT_LVDS";
    "8" = "D3DKMDT_VOT_D_JPN";
    "9" = "D3DKMDT_VOT_SDI";
    "10" = "D3DKMDT_VOT_DISPLAYPORT_EXTERNAL";
    "11" = "D3DKMDT_VOT_DISPLAYPORT_EMBEDDED";
    "12" = "D3DKMDT_VOT_UDI_EXTERNAL";
    "13" = "D3DKMDT_VOT_UDI_EMBEDDED";
    "14" = "D3DKMDT_VOT_SDTVDONGLE";
    "15" = "D3DKMDT_VOT_MIRACAST";
    "2147483648" = "D3DKMDT_VOT_INTERNAL";
}

#Takes each computer specified and runs the following code:
ForEach ($Computer in $ComputerName) {
    "Running PowerShell $($PSVersionTable.PSVersion)."

    #Grabs the Monitor objects from WMI
    $Monitors = Get-WMIObject -Namespace root\WMI -Class "WMIMonitorID" `
        -ComputerName $Computer -ErrorAction SilentlyContinue

    #Creates an empty array to hold the data
    $Monitor_Array = @()


    #Takes each monitor object found and runs the following code:
    ForEach ($Monitor in $Monitors) {

        $filter = ("InstanceName = '$($monitor.InstanceName)'").Replace("`\", "`\`\")
        #Get Horizontal and Vertical screen measurements, and calculate the diagonal size.
        $BasicDisplayParameters = Get-WMIObject -Namespace root\WMI `
            -ClassName WmiMonitorBasicDisplayParams -ComputerName $Computer `
            -Filter $filter -ErrorAction SilentlyContinue 
            $a = [System.Math]::Pow($BasicDisplayParameters.MaxHorizontalImageSize/2.54,2)
            $b = [System.Math]::Pow($BasicDisplayParameters.MaxVerticalImageSize/2.54,2)
            [string]$Mon_Size = [System.Math]::Round([System.Math]::Sqrt($a + $b))
        
        #Get monitor output ID and lookup friendly name (eg: DisplayPort)
        $ConnectionParameters = Get-WMIObject -Namespace root\WMI `
            -ClassName WmiMonitorConnectionParams -ComputerName $Computer `
            -Filter $filter -ErrorAction SilentlyContinue 
        [string]$OutputType = $ConnectionParameters.VideoOutputTechnology
        $Mon_Output_Type = $InputTypeHash.$OutputType
        $Mon_Raw_Output_Type = $RawInputTypeHash.$OutputType

        #Find the maximum screen resolution supported by the display
        $maxres = Get-WMIObject -Namespace root\wmi `
            -ClassName WmiMonitorListedSupportedSourceModes -ComputerName $Computer `
            -Filter $filter -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty MonitorSourceModes | 
            Sort-Object -Property {$_.HorizontalActivePixels * $_.VerticalActivePixels} -Descending |
            Select-Object -First 1
        $Mon_Max_Resolution = "$($maxres.HorizontalActivePixels)x$($maxres.VerticalActivePixels)"

        #Grabs respective data and converts it from ASCII encoding and removes any trailing ASCII null values
        If ($Monitor.UserFriendlyNameLength -gt 0) {
            $Mon_Model = ([System.Text.Encoding]::ASCII.GetString($Monitor.UserFriendlyName)).Replace("$([char]0x0000)","")
        } else {
            $Mon_Model = 'NA'
        }
        #If the display is internal to the device, ignore the serial number field
        If ($InputTypeHash.$OutputType -ne 'Internal') {
            $Mon_Serial_Number = ([System.Text.Encoding]::ASCII.GetString($Monitor.SerialNumberID)).Replace("$([char]0x0000)","")
        } else {
            $Mon_Serial_Number = 'NA'
        }

        $Mon_Manufacturer = ([System.Text.Encoding]::ASCII.GetString($Monitor.ManufacturerName)).Replace("$([char]0x0000)","")
        $Mon_WeekOfManufacture = ($Monitor.WeekOfManufacture)
        $Mon_YearOfManufacture = ($Monitor.YearOfManufacture)

        #Sets a friendly name based on the hash table above. If no entry found sets it to
        #the original three character code
        $Mon_Manufacturer_Friendly = $ManufacturerHash.$Mon_Manufacturer
        If ($Mon_Manufacturer_Friendly -eq $null) {
            $Mon_Manufacturer_Friendly = $Mon_Manufacturer
        }
        #Creates a custom monitor object and fills it with NoteProperty members and the
        #respective data.  The data fields vary by the number of computers being targeted.
        If ($ComputerName.Count -gt 1) {
            $Monitor_Obj = [PSCustomObject]@{
                Computer = $Computer
                Manufacturer = $Mon_Manufacturer_Friendly
                Model = $Mon_Model
                SerialNumber = $Mon_Serial_Number
                Week = $Mon_WeekOfManufacture
                Year = $Mon_YearOfManufacture
                Connection = $Mon_Output_Type
                #RawConnectionData = $Mon_Raw_Output_Type
                Size = $Mon_Size
                MaxResolution = $Mon_Max_Resolution
            }            
        } else {
            $Monitor_Obj = [PSCustomObject]@{

                Manufacturer = $Mon_Manufacturer_Friendly
                Model = $Mon_Model
                SerialNumber = $Mon_Serial_Number
                Week = $Mon_WeekOfManufacture
                Year = $Mon_YearOfManufacture
                Connection = $Mon_Output_Type
                #RawConnectionData = $Mon_Raw_Output_Type
                Size = $Mon_Size
                MaxResolution = $Mon_Max_Resolution
            }
        }

        #Appends the object to the array
        $Monitor_Array += $Monitor_Obj

    } #End ForEach Monitor

    #Outputs the Array
    $Monitor_Array

} #End ForEach Computer