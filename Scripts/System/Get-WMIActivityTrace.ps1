Install-Module -Name Join-Object -AcceptLicense  
Add-Type @"
using System;
using System.Runtime.InteropServices;

namespace Utility
{
  public class PriorityHelper
  {
    [DllImport("kernel32.dll", CharSet=CharSet.Auto, SetLastError=true)]
    static extern bool SetPriorityClass(IntPtr handle, PriorityClass priorityClass);

    public enum PriorityClass : uint
    {
        ABOVE_NORMAL_PRIORITY_CLASS = 0x8000,
        BELOW_NORMAL_PRIORITY_CLASS = 0x4000,
        HIGH_PRIORITY_CLASS = 0x80,
        IDLE_PRIORITY_CLASS = 0x40,
        NORMAL_PRIORITY_CLASS = 0x20,
        PROCESS_MODE_BACKGROUND_BEGIN = 0x100000,// 'Windows Vista/2008 and higher
        PROCESS_MODE_BACKGROUND_END = 0x200000,//   'Windows Vista/2008 and higher
        REALTIME_PRIORITY_CLASS = 0x100
    }

    public static int SetBackgroundIoPriority ()
    {
        IntPtr id = System.Diagnostics.Process.GetCurrentProcess().Handle;
        if (SetPriorityClass(id, PriorityClass.PROCESS_MODE_BACKGROUND_BEGIN)) return (int) id;
        return -1;
    }
    public static int UnSetBackgroundIoPriority ()
    {
        IntPtr id = System.Diagnostics.Process.GetCurrentProcess().Handle;
        if (SetPriorityClass(id, PriorityClass.PROCESS_MODE_BACKGROUND_END)) return (int) id;
        return -2;
    }

  }
}
"@

#Enable WMI Tracing Log
$ComputerName = $env:COMPUTERNAME
$StartTime = Get-Date
$LogStartTime = Get-Date $StartTime -format "yyyy-MM-dd_HH-mm"

#Set Script Process CPU  Priority to Idle and IO Priority to Background
#If (Test-Path Variable:PSDebugContext) {
#    (Get-Process -id $PID).PriorityClass = 'Normal'
#}
#Else {
#    (Get-Process -id $PID).PriorityClass = 'Idle'
#    Try {
#    $result = [Utility.PriorityHelper]::SetBackgroundIoPriority()
#    if ($result -eq -1) {
#        throw "Background IO priority could not be set or is already set"
#    }
#}
#Catch { }
#}

$ProcessHashTable = $null
$ProcessHashTable = @{ }
$beforeprocesses = get-process
foreach ($beforeprocess in $beforeprocesses) {
    If ($beforeprocess.name.Length -gt 0 -and $beforeprocess.id -notin $ProcessHashTable.Keys ) {
        $beforeprocessleaf = Try { $beforeprocess.Path | Split-Path -Leaf -Resolve -ErrorAction Stop } Catch { $beforeprocess.Name }
        Try {
            $ProcessHashTable.Add([string]$processbefore.id, $beforeprocessleaf )
        }
        Catch { }
    }    
}

$WMITracingLog = 'Microsoft-Windows-WMI-Activity/Trace'
(wevtutil set-log "$WMITracingLog" /enabled:false) | Out-Null
Write-Output y | wevtutil set-log "$WMITracingLog" /enabled:true /quiet:true #Note that this will clear the WMI Tracing Log

# enable audit process tracking in the security event log
$auditkey = 'hklm:\software\microsoft\windows\currentversion\policies\system\audit'
Get-Item $auditkey | New-ItemProperty  -Name processcreationincludecmdline_enabled -Value 1 -PropertyType dword -Force | Out-Null
auditpol.exe /set /subcategory:"process creation" /success:enable
auditpol.exe /set /subcategory:"process termination" /success:enable

start-sleep -seconds 180

wevtutil set-log "$WMITracingLog" /enabled:false
auditpol.exe /set /subcategory:"process creation" /success:disable
auditpol.exe /set /subcategory:"process termination" /success:disable
$ProcessHashTable = $null
$ProcessHashTable = @{ }
$afterprocesses = get-process
foreach ($afterprocess in $afterprocesses) {
    If ($afterprocess.name.Length -gt 0 -and $afterprocess.id -notin $ProcessHashTable.Keys ) {
        $afterprocessleaf = Try { $afterprocess.Path | Split-Path -Leaf -Resolve -ErrorAction Stop } Catch { $afterprocess.Name }
        Try {
            $ProcessHashTable.Add([string]$afterprocess.id, $afterprocessleaf)
        }
        Catch { }
    }    
}

$WMIEventLog = Get-WinEvent -FilterHashtable @{Logname = $WMITracingLog; ID = 11 } -Oldest #StartTime=$StartTime;
$SecurityEventLog = Get-WinEvent -FilterHashtable @{Logname = 'Security'; StartTime = $StartTime.AddHours(-2); ID = 4688, 4689 } -Oldest

$SecurityObjects = $null
$SecurityObjects = @()
foreach ($event in $SecurityEventLog) {
    $xmlevent = ([xml]$event.ToXml()).Event
    $DateTime = ($event.TimeCreated | Get-Date -Format g)
    [string]$HexPID = ($xmlevent.EventData.Data | Where-Object { $_.Name -eq 'NewProcessId' } | Select-Object '#text').'#text'
    [string]$ProcessID = If ($HexPID.Length -gt 1) { [System.Convert]::ToInt64($HexPID, 16) }
    [string]$NewProcessName = ($xmlevent.EventData.Data | Where-Object { $_.Name -eq 'NewProcessName' } | Select-Object '#text').'#text'
    [string]$ProcessName = If ($NewProcessName) { Try { $NewProcessName | Split-Path -Leaf -Resolve -ErrorAction Stop } Catch { } }
    [string]$ParentProcessName = ($xmlevent.EventData.Data | Where-Object { $_.Name -eq 'ParentProcessName' } | Select-Object '#text').'#text'
    [string]$RawCommandLine = ($xmlevent.EventData.Data | Where-Object { $_.Name -eq 'CommandLine' } | Select-Object '#text').'#text'
    $SecurityData = $null
    $SecurityData = [PSCustomObject] @{
        TimeCreated       = $DateTime
        ProcessID         = $ProcessID
        ProcessName       = $ProcessName
        ParentProcessName = $ParentProcessName
        CommandLine       = $RawCommandLine
    }
    If ($ProcessName.Length -gt 0 -and $ProcessId -notin $ProcessHashTable.Keys ) {
        Try {
            $ProcessHashTable.Add([string]$ProcessID, $ProcessName)
        }
        Catch { }
    }    
    $SecurityObjects += $SecurityData
}

$WMIObjects = $null
$WMIObjects = @()
foreach ($entry in $WMIEventLog) {
    $xmlentry = ([xml]$entry.ToXml()).Event
    [string]$WMI_ClientProcessID = $xmlentry.UserData.Operation_New.ClientProcessId
    [string]$WMI_ProcessName = $ProcessHashTable.$WMI_ClientProcessID
    [DateTime]$WMI_OperationStartTime = $xmlentry.System.TimeCreated.SystemTime
    [Int64]$WMI_OperationCPUTicks = $xmlentry.System.Execution.KernelTime + $xmlentry.System.Execution.UserTime
    $WMI_OperationStopTime = $WMI_OperationStartTime.AddTicks($WMI_OperationCPUTicks)
    $WMI_OperationElapsedTime = ($WMI_OperationStopTime - $WMI_OperationStartTime).TotalMilliseconds
    [string]$WMI_Operation = $xmlentry.UserData.Operation_New.Operation
    [string]$WMI_Namespace = If ($WMI_Operation -match 'ExecQuery') { $WMI_Operation -replace '.* - (.*) : (.*)', '$1' }
    [string]$WMI_Query = If ($WMI_Operation -match 'ExecQuery') { $WMI_Operation -replace '.* - (.*) : (.*)', '$2' }
    $WMIData = $null
    $WMIData = [PSCustomObject] @{
        ProcessID            = $WMI_ClientProcessID
        ProcessName          = $WMI_ProcessName
        OperationStartTime   = $WMI_OperationStartTime
        OperationStopTime    = $WMI_OperationStopTime
        OperationElapsedTime = $WMI_OperationElapsedTime
        Operation            = $WMI_Operation
        Namespace            = $WMI_Namespace
        Query                = $WMI_Query
    }
    $WMIObjects += $WMIData
}

$JoinParams = @{
    Left              = $WMIObjects
    Right             = $SecurityObjects
    LeftJoinProperty  = 'ProcessID'
    RightJoinProperty = 'ProcessID'
    LeftProperties    = "*"
    RightProperties   = "*"
    Prefix            = "sec_"
    Type              = 'AllInLeft'

}

$CombinedObject = $null
$CombinedObject = Join-Object @JoinParams

(Get-Process -id $PID).PriorityClass = 'Normal'
Try {
    $result = [Utility.PriorityHelper]::UnSetBackgroundIoPriority()
    if ($result -eq -2) {
        throw "Background IO priority could not be unset"
    }
}
Catch { }


$CombinedObject | Select-Object -Property `
@{Name = "Computer Name"; Expression = { $ComputerName } },
@{Name = "Time Created"; Expression = { $_.sec_TimeCreated.ToString() } },
@{Name = "Process ID"; Expression = { $_.ProcessID } },
ProcessName,
Operation,
@{Name = "WMI Namespace"; Expression = { $_.Namespace } },
@{Name = "WMI Query"; Expression = { $_.Query } },
@{Name = "WMI Operation Start Time"; Expression = { $_.OperationStartTime } },
@{Name = "WMI Operation Stop Time"; Expression = { $_.OperationStopTime } },
@{Name = "WMI Operation Elapsed Time (ms)"; Expression = { $_.OperationElapsedTime } },
@{Name = "Command Line" ; Expression = { $_.sec_CommandLine } },
@{Name = "Parent Process Name" ; Expression = { $_.sec_ParentProcessName } } `
| Group-Object -Property Operation


#Export-Csv -Path ("C:\DesktopSupportTools\WMIUsage-$env:COMPUTERNAME $LogStartTime.csv").Replace(" ", "_") -NoTypeInformation -Force