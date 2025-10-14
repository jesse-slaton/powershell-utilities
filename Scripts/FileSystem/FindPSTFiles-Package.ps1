Function SetPriorityClasses {
    [CmdletBinding()]
    Param (
        [string]$ProcessName,
        [int]$ProcID,
        [ValidateSet("Idle", "Normal", "High", "RealTime")]
        [string]$CpuPriorityClass = "Idle",
        [ValidateRange(1, 5)]
        [int]$MemoryPriority = 1,
        [ValidateRange(0, 5)]
        [int]$IoPriority = 0
    )

    # If you can't run, execute this first from an elevated PowerShell Prompt - set-executionpolicy remotesigned
    #    If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {   
    #        $arguments = "& '" + $myinvocation.mycommand.definition + "'"
    #        Start-Process powershell -Verb runAs -ArgumentList $arguments
    #        Break
    #    }

    Add-Type @"
using System;
using System.Runtime.InteropServices;

namespace SysWin32
{
    public enum PROCESS_INFORMATION_CLASS
    {
        ProcessMemoryPriority,
        ProcessInformationClassMax,
    }

    [System.Runtime.InteropServices.StructLayoutAttribute(System.Runtime.InteropServices.LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION
    {
        public uint Information;
    }

    public partial class NativeMethods {
        [System.Runtime.InteropServices.DllImportAttribute("kernel32.dll", EntryPoint="GetCurrentProcess", SetLastError=true)]
        public static extern System.IntPtr GetCurrentProcess();

        [System.Runtime.InteropServices.DllImportAttribute("kernel32.dll", EntryPoint="OpenProcess", SetLastError=true)]
        public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, uint dwProcessId);

        [System.Runtime.InteropServices.DllImportAttribute("kernel32.dll", EntryPoint="SetProcessInformation", SetLastError=true)]
        public static extern bool SetProcessInformation(System.IntPtr hProcess, PROCESS_INFORMATION_CLASS ProcessInformationClass, System.IntPtr ProcessInformation, uint ProcessInformationSize) ;
    }
}

namespace SysWinNT
{
    public enum PROCESS_INFORMATION_CLASS
    {
        ProcessBasicInformation,
        ProcessQuotaLimits,
        ProcessIoCounters,
        ProcessVmCounters,
        ProcessTimes,
        ProcessBasePriority,
        ProcessRaisePriority,
        ProcessDebugPort,
        ProcessExceptionPort,
        ProcessAccessToken,
        ProcessLdtInformation,
        ProcessLdtSize,
        ProcessDefaultHardErrorMode,
        ProcessIoPortHandlers,          // Note: this is kernel mode only
        ProcessPooledUsageAndLimits,
        ProcessWorkingSetWatch,
        ProcessUserModeIOPL,
        ProcessEnableAlignmentFaultFixup,
        ProcessPriorityClass,
        ProcessWx86Information,
        ProcessHandleCount,
        ProcessAffinityMask,
        ProcessPriorityBoost,
        ProcessDeviceMap,
        ProcessSessionInformation,
        ProcessForegroundInformation,
        ProcessWow64Information,
        ProcessImageFileName,
        ProcessLUIDDeviceMapsEnabled,
        ProcessBreakOnTermination,
        ProcessDebugObjectHandle,
        ProcessDebugFlags,
        ProcessHandleTracing,
        ProcessIoPriority,
        ProcessExecuteFlags,
        ProcessTlsInformation,
        ProcessCookie,
        ProcessImageInformation,
        ProcessCycleTime,
        ProcessPagePriority,
        ProcessInstrumentationCallback,
        ProcessThreadStackAllocation,
        ProcessWorkingSetWatchEx,
        ProcessImageFileNameWin32,
        ProcessImageFileMapping,
        ProcessAffinityUpdateMode,
        ProcessMemoryAllocationMode,
        ProcessGroupInformation,
        ProcessTokenVirtualizationEnabled,
        ProcessConsoleHostProcess,
        ProcessWindowInformation,
        MaxProcessInfoClass             // MaxProcessInfoClass should always be the last enum
    }

    public partial class NativeMethods {
        [System.Runtime.InteropServices.DllImportAttribute("ntdll.dll", EntryPoint="NtSetInformationProcess")]
        public static extern int NtSetInformationProcess(System.IntPtr hProcess, PROCESS_INFORMATION_CLASS processInformationClass, System.IntPtr ProcessInformation, uint ProcessInformationSize);
    }
}
"@

    $OverallResult = 0

    
    If ($null -eq $ProcID) {
        $Process = Get-Process $ProcessName
        $ProcessId = $Process.id 
    }
    Else {
        $ProcessId = $ProcID
        $Process = Get-Process -Id $ProcID
    }
    Try {
        $Process.PriorityClass = $CpuPriorityClass
    }
    Catch {
        Write-Host -BackgroundColor Black -ForegroundColor Red "Error setting process priority  - $($_.Exception.Message)"
        Pause
        $OverallResult = 1
        exit $OverallResult
    }
    Write-Host -ForegroundColor Green ("Set CPU priority on {0} ({1}) to be {2}" -f $ProcessName, $ProcessId, $CpuPriorityClass)

    #    4096 or     0x1000 = PROCESS_QUERY_LIMITED_INFORMATION
    # 1056763 or 0x00101ffb = PROCESS_ALL_ACCESS
    $DesiredAccess = 0x00101ffb
    $InheritHandle = $false
    $hProcess = [SysWin32.NativeMethods]::OpenProcess($DesiredAccess, $InheritHandle, $ProcessId);
    $LastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if ($hProcess -eq 0) {
        Write-Host -BackgroundColor Black -ForegroundColor Red "Failed to open Win32 process.  Error: $(([ComponentModel.Win32Exception] $LastError).Message)"
        Pause
        $OverallResult = 2
        Return $OverallResult
    }
    Write-Host -ForegroundColor Green ("Successfully got handle - {0}" -f $hProcess)

    $memInfo = New-Object SysWin32.PROCESS_INFORMATION
    $memInfo.Information = $MemoryPriority
    $memInfoSize = [System.Runtime.Interopservices.Marshal]::SizeOf($memInfo)
    $memInfoPtr = [System.Runtime.Interopservices.Marshal]::AllocHGlobal($memInfoSize)
    [System.Runtime.Interopservices.Marshal]::StructureToPtr($memInfo, $memInfoPtr, $false)
    $result = [SysWin32.NativeMethods]::SetProcessInformation($hProcess, [SysWin32.PROCESS_INFORMATION_CLASS]::ProcessMemoryPriority, $memInfoPtr, $memInfoSize)
    $LastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if (!$result) {
        $OverallResult = 3
        Write-Host -BackgroundColor Black -ForegroundColor Red ("Failed to set memory priority on {0} ({1}) to be {2}.  Error: {3}" -f $ProcessName, $ProcessId, $MemoryPriority, ([ComponentModel.Win32Exception]$LastError).Message)
    }
    else {
        Write-Host -ForegroundColor Green ("Set memory priority on {0} ({1}) to be {2}." -f $ProcessName, $ProcessId, $MemoryPriority)
    }

    $ioInfo = New-Object SysWin32.PROCESS_INFORMATION
    $ioInfo.Information = $IoPriority
    $ioInfoSize = [System.Runtime.Interopservices.Marshal]::SizeOf($ioInfo)
    $ioInfoPtr = [System.Runtime.Interopservices.Marshal]::AllocHGlobal($ioInfoSize)
    [System.Runtime.Interopservices.Marshal]::StructureToPtr($ioInfo, $ioInfoPtr, $false)
    $result = [SysWinNT.NativeMethods]::NtSetInformationProcess($hProcess, [SysWinNT.PROCESS_INFORMATION_CLASS]::ProcessIoPriority, $ioInfoPtr, $ioInfoSize)
    $LastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if ($result -ne 0) {
        $OverallResult = 4
        Write-Host -BackgroundColor Black -ForegroundColor Red ("Failed to set IO priority on {0} ({1}) to be {2}.  Result: {3}.  Error: {4}" -f $ProcessName, $ProcessId, $IoPriority, $result, ([ComponentModel.Win32Exception]$LastError).Message)
    }
    else {
        Write-Host -ForegroundColor Green ("Set IO priority on {0} ({1}) to be {2}" -f $ProcessName, $ProcessId, $IoPriority)
    }
    Return $OverallResult
}

Function FormatFileSize() {
    Param ([int64]$size)
    If ($size -gt 1TB) { [string]::Format("{0:0.00} TB", $size / 1TB) }
    ElseIf ($size -gt 1GB) { [string]::Format("{0:0.00} GB", $size / 1GB) }
    ElseIf ($size -gt 1MB) { [string]::Format("{0:0.00} MB", $size / 1MB) }
    ElseIf ($size -gt 1KB) { [string]::Format("{0:0.00} kB", $size / 1KB) }
    ElseIf ($size -gt 0) { [string]::Format("{0:0.00} B", $size) }
    Else { "" }
}

#Get PID of this running instance
$CurrentPID = [System.Diagnostics.Process]::GetCurrentProcess().Id
#Change Priority to Idle/Idle/Background
$Null = SetPriorityClasses -ProcID $CurrentPID -CpuPriorityClass Idle -MemoryPriority 1 -IoPriority 0
#Enumarate all mapped drives, omitting network shares
$Drives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType <> 4"

#Crawl filesystem for PST files
$PSTFiles = Foreach ($Drive in $Drives) {
    $Items = Get-ChildItem -Path "$($Drive.DeviceID)\" -Filter *.pst -Recurse -ErrorAction Ignore
    ForEach ($Item in $Items) {
        $Object = [PSCustomObject]@{
            Name          = $Item.FullName
            LastWriteTime = $Item.LastWriteTime
            Size          = FormatFileSize($Item.Length)
        }
    }
    $Object
}

#Output results to JSON file
$PSTFiles
$PSTFiles | Select-Object FullName, LastWriteTime | ConvertTo-Json | Out-File -FilePath C:\Support\Logs\PSTFiles.json