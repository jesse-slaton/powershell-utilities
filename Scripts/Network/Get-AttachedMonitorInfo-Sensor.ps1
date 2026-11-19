#Requires -Version 3.0
<#
.SYNOPSIS
    Reports the monitors attached to one or more computers, from the EDID data in WMI.

.DESCRIPTION
    For each computer, reads the WmiMonitorID, WmiMonitorBasicDisplayParams,
    WmiMonitorConnectionParams and WmiMonitorListedSupportedSourceModes classes in the
    root\WMI namespace, and reports each monitor's manufacturer, model, serial number,
    week and year of manufacture, connection type, diagonal size in inches, and maximum
    resolution. Three-letter EDID manufacturer codes are translated with a built-in
    table; if the CSV named by -ManufacturerCsvPath exists, its entries are added to
    (and override) the built-in table.

    Two output formats:
    - Object (default): one object per monitor. A Computer property is added when more
      than one computer is queried.
    - Delimited: one pipe-delimited line per monitor, written to the host, for use as a
      deployment-tool sensor:
      Manufacturer|Model|SerialNumber|Week|Year|Connection|Size|MaxResolution|InstanceName

    This script replaces the former Get-AttachedMonitorInfo_-Sensor.ps1; run it with
    -OutputFormat Delimited for that script's output.

.PARAMETER ComputerName
    Computers to query. Defaults to the local computer.

.PARAMETER OutputFormat
    Object (default) returns objects. Delimited writes one pipe-delimited line per
    monitor, the format of the former Get-AttachedMonitorInfo_-Sensor.ps1.

.PARAMETER ManufacturerCsvPath
    Optional CSV of EDID manufacturer codes with '#Fields:ID' and 'Manufacturer'
    columns. Used only when the file exists. Defaults to
    C:\DesktopSupportTools\Dictionaries\edid_manufacturers.csv.

.EXAMPLE
    .\Get-AttachedMonitorInfo-Sensor.ps1

    Manufacturer  : HP
    Model         : HP E243i
    SerialNumber  : CNK7290KPM
    Week          : 29
    Year          : 2017
    Connection    : Displayport
    Size          : 24
    MaxResolution : 1920x1200

.EXAMPLE
    .\Get-AttachedMonitorInfo-Sensor.ps1 -OutputFormat Delimited

    HP|HP E243i|CNK7290KPM|29|2017|Displayport|24|1920x1200|DISPLAY\HPN3401\5&2d0c1b1&0&UID4352_0

.EXAMPLE
    .\Get-AttachedMonitorInfo-Sensor.ps1 -ComputerName PC01, PC02

    Returns one object per monitor on each computer, with a Computer property.

.NOTES
    Requires Windows and the root\WMI monitor classes (present on Windows 7 and later).
    Querying a remote computer needs WMI/DCOM access to it. Uses Get-WmiObject, so it
    runs on Windows PowerShell 5.1; conversion to CIM is tracked in issue #49.
#>

[CmdletBinding()]
param (
    [Parameter(ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True)]
    [String[]]$ComputerName = $env:ComputerName,

    [ValidateSet('Object', 'Delimited')]
    [string]$OutputFormat = 'Object',

    [string]$ManufacturerCsvPath = 'C:\DesktopSupportTools\Dictionaries\edid_manufacturers.csv'
)

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

#Entries from the optional CSV add to, and override, the built-in table.
if ($ManufacturerCsvPath -and (Test-Path -LiteralPath $ManufacturerCsvPath)) {
    Import-Csv -LiteralPath $ManufacturerCsvPath | ForEach-Object { $ManufacturerHash[$_."#Fields:ID"] = $_.Manufacturer }
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

#Takes each computer specified and runs the following code:
ForEach ($Computer in $ComputerName) {
    if ($OutputFormat -eq 'Object') {
        "Running PowerShell $($PSVersionTable.PSVersion)."
    }

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
        $a = [System.Math]::Pow($BasicDisplayParameters.MaxHorizontalImageSize / 2.54, 2)
        $b = [System.Math]::Pow($BasicDisplayParameters.MaxVerticalImageSize / 2.54, 2)
        [string]$Mon_Size = [System.Math]::Round([System.Math]::Sqrt($a + $b))

        #Get monitor output ID and lookup friendly name (eg: DisplayPort)
        $ConnectionParameters = Get-WMIObject -Namespace root\WMI `
            -ClassName WmiMonitorConnectionParams -ComputerName $Computer `
            -Filter $filter -ErrorAction SilentlyContinue
        [string]$OutputType = $ConnectionParameters.VideoOutputTechnology
        $Mon_Output_Type = $InputTypeHash.$OutputType

        #Find the maximum screen resolution supported by the display
        $maxres = Get-WMIObject -Namespace root\wmi `
            -ClassName WmiMonitorListedSupportedSourceModes -ComputerName $Computer `
            -Filter $filter -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty MonitorSourceModes |
            Sort-Object -Property { $_.HorizontalActivePixels * $_.VerticalActivePixels } -Descending |
            Select-Object -First 1
        $Mon_Max_Resolution = "$($maxres.HorizontalActivePixels)x$($maxres.VerticalActivePixels)"

        #Grabs respective data and converts it from ASCII encoding and removes any trailing ASCII null values
        If ($Monitor.UserFriendlyNameLength -gt 0) {
            $Mon_Model = ([System.Text.Encoding]::ASCII.GetString($Monitor.UserFriendlyName)).Replace("$([char]0x0000)", "")
        }
        else {
            $Mon_Model = 'NA'
        }
        #If the display is internal to the device, ignore the serial number field
        If ($InputTypeHash.$OutputType -ne 'Internal') {
            $Mon_Serial_Number = ([System.Text.Encoding]::ASCII.GetString($Monitor.SerialNumberID)).Replace("$([char]0x0000)", "")
        }
        else {
            $Mon_Serial_Number = 'NA'
        }

        $Mon_Manufacturer = ([System.Text.Encoding]::ASCII.GetString($Monitor.ManufacturerName)).Replace("$([char]0x0000)", "")
        $Mon_WeekOfManufacture = ($Monitor.WeekOfManufacture)
        $Mon_YearOfManufacture = ($Monitor.YearOfManufacture)

        #Sets a friendly name based on the table above. If no entry found sets it to
        #the original three character code
        $Mon_Manufacturer_Friendly = $ManufacturerHash.$Mon_Manufacturer
        If (-not $Mon_Manufacturer_Friendly) {
            $Mon_Manufacturer_Friendly = $Mon_Manufacturer
        }

        if ($OutputFormat -eq 'Delimited') {
            [String]$retVal = $Mon_Manufacturer_Friendly + "|" + $Mon_Model + "|" + $Mon_Serial_Number + "|" + $Mon_WeekOfManufacture + "|" +
            $Mon_YearOfManufacture + "|" + $Mon_Output_Type + "|" + $Mon_Size + "|" + $Mon_Max_Resolution + "|" + $Monitor.InstanceName
            Write-Host $retVal
            continue
        }

        #Creates a custom monitor object. The Computer property is added when more than one computer is targeted.
        If ($ComputerName.Count -gt 1) {
            $Monitor_Obj = [PSCustomObject]@{
                Computer      = $Computer
                Manufacturer  = $Mon_Manufacturer_Friendly
                Model         = $Mon_Model
                SerialNumber  = $Mon_Serial_Number
                Week          = $Mon_WeekOfManufacture
                Year          = $Mon_YearOfManufacture
                Connection    = $Mon_Output_Type
                Size          = $Mon_Size
                MaxResolution = $Mon_Max_Resolution
            }
        }
        else {
            $Monitor_Obj = [PSCustomObject]@{
                Manufacturer  = $Mon_Manufacturer_Friendly
                Model         = $Mon_Model
                SerialNumber  = $Mon_Serial_Number
                Week          = $Mon_WeekOfManufacture
                Year          = $Mon_YearOfManufacture
                Connection    = $Mon_Output_Type
                Size          = $Mon_Size
                MaxResolution = $Mon_Max_Resolution
            }
        }

        #Appends the object to the array
        $Monitor_Array += $Monitor_Obj

    } #End ForEach Monitor

    #Outputs the Array
    $Monitor_Array

} #End ForEach Computer
