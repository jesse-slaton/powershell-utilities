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
#Get-Variable -Include AMI_*,MON_* | Clear-Variable
$MonitorArray = @()

#List of Manufacture Codes that could be pulled from WMI and their respective full names.
$ManufacturerHash = @{
    "ACI" = " Asus";
    "ACR" = "Acer";
    "APP" = "Apple Computer";
    "AUO" = "Asus";
    "BOE" = "BOE";
    "BBY" = "Insignia";
    "BJK" = "DisplayLink";
    "CEI" = "Crestron";
    "CHE" = "Acer";
    "CMN" = "Chimei Innolux";
    "CMO" = "Acer";
    "DEL" = "Dell";
    "DLL" = "Dell";
    "ELE" = "Element";
    "GSM" = "LG";
    "GWY" = "Gateway 2000";
    "HEC" = "Hisense Electric";
    "HJW" = "Tendak";
    "HPC" = "HP";
    "HPD" = "HP";
    "HPN" = "HP";
    "HPQ" = "HP";
    "HWP" = "HP";
    "HSG" = "HANNspree";
    "KYK" = "Samsung";
    "LEN" = "Lenovo";
    "LGD" = "LG";
    "LGS" = "LG";
    "LIN" = "Lenovo";
    "LNV" = "Lenovo";
    "MCT" = "Microtec";
    "NCT" = "NEC";
    "NEC" = "NEC";
    "NMV" = "NEC";
    "NVD" = "Nvidia";
    "PRT" = "Princeton";
    "SAM" = "Samsung";
    "SAN" = "Samsung";
    "SEC" = "HP";
    "SEM" = "Samsung";
    "SKT" = "Samsung";
    "SNY" = "Sony";
    "SSE" = "Samsung";
    "STN" = "Samsung";
    "SYN" = "Synaptics";
    "VIZ" = "Vizio";
    "VSC" = "ViewSonic";
}

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

    #Grabs the Monitor objects from WMI
    $AMI_Monitors = Get-WMIObject -Namespace root\WMI -Class "WMIMonitorID" `
        -ErrorAction SilentlyContinue

    #Takes each monitor object found and runs the following code:
    ForEach ($AMI_Monitor in $AMI_Monitors) {

        $AMI_Filter = ("InstanceName = '$($AMI_Monitor.InstanceName)'").Replace("`\", "`\`\")
        $AMI_BasicDisplayParameters = Get-WMIObject -Namespace root\WMI `
            -ClassName WmiMonitorBasicDisplayParams `
            -Filter $AMI_Filter -ErrorAction SilentlyContinue 
            $a = [System.Math]::Pow($AMI_BasicDisplayParameters.MaxHorizontalImageSize/2.54,2)
            $b = [System.Math]::Pow($AMI_BasicDisplayParameters.MaxVerticalImageSize/2.54,2)
            $Mon_Size = [System.Math]::Round([System.Math]::Sqrt($a + $b))

        $AMI_ConnectionParameters = Get-WMIObject -Namespace root\WMI `
            -ClassName WmiMonitorConnectionParams `
            -Filter $AMI_Filter -ErrorAction SilentlyContinue 
        [string]$AMI_OutputType = $AMI_ConnectionParameters.VideoOutputTechnology
        $Mon_Output_Type = $InputTypeHash.$AMI_OutputType

        $AMI_MaxRes = Get-WMIObject -Namespace root\wmi `
            -ClassName WmiMonitorListedSupportedSourceModes `
            -Filter $AMI_Filter -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty MonitorSourceModes | 
            Sort-Object -Property {$_.HorizontalActivePixels * $_.VerticalActivePixels} -Descending |
            Select-Object -First 1
        $Mon_Max_Resolution = "$($AMI_MaxRes.HorizontalActivePixels)x$($AMI_MaxRes.VerticalActivePixels)"

        #Grabs respective data and converts it from ASCII encoding and removes any trailing ASCII null values
        If ($AMI_Monitor.UserFriendlyNameLength -gt 0) {
            $Mon_Model = ([System.Text.Encoding]::ASCII.GetString($AMI_Monitor.UserFriendlyName)).Replace("$([char]0x0000)","")
        } else {
            $Mon_Model = 'NA'
        }
        If ($InputTypeHash.$AMI_OutputType -ne 'Internal') {
            $Mon_Serial_Number = ([System.Text.Encoding]::ASCII.GetString($AMI_Monitor.SerialNumberID)).Replace("$([char]0x0000)","")
        } else {
            $Mon_Serial_Number = 'NA'
        }
        $Mon_InstanceName = $AMI_Monitor.InstanceName
        $Mon_Manufacturer = ([System.Text.Encoding]::ASCII.GetString($AMI_Monitor.ManufacturerName)).Replace("$([char]0x0000)","")
        $Mon_WeekOfManufacture = ($AMI_Monitor.WeekOfManufacture)
        $Mon_YearOfManufacture = ($AMI_Monitor.YearOfManufacture)

        #Sets a friendly name based on the hash table above. If no entry found sets it to
        #the original three character code
        $Mon_Manufacturer_Friendly = $ManufacturerHash.$Mon_Manufacturer
        If (!($Mon_Manufacturer_Friendly)) {
            $Mon_Manufacturer_Friendly = $Mon_Manufacturer
        }
       
        [String]$retVal = $Mon_Manufacturer_Friendly + "|" + $Mon_Model + "|" + $Mon_Serial_Number + "|" + $Mon_WeekOfManufacture  + "|" + 
        $Mon_YearOfManufacture + "|" + $Mon_Output_Type + "|" + $Mon_Size + "|" + $Mon_Max_Resolution + "|" + $Mon_InstanceName

        #Do not return details on a laptop's built-in screen
 #       If ($Mon_Output_Type -ne 'Internal') {
            Write-Host $retVal
  #      }
    }