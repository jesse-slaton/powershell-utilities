<#
.SYNOPSIS
    Reports the computer's approximate street address, coordinates and public IP address as one pipe-delimited line.

.DESCRIPTION
    Asks the Windows location service for the device position through the Windows
    Runtime Geolocator (Windows.Devices.Geolocation.Geolocator), called from a small
    C# helper compiled with Add-Type. A position up to one minute old is accepted.
    When location is turned off, denied to desktop apps, or does not answer within
    -TimeoutSeconds, the script stops with a terminating error that says why.

    Otherwise it gets the public IP address from http://ifconfig.me/ip and
    reverse-geocodes the full-precision coordinates with the OpenStreetMap Nominatim
    service. Outputs one line in this form:
    <Road>|<City>|<State>|<CountryCode>|<Latitude>|<Longitude>|<PublicIP>
    with latitude and longitude rounded to two decimal places. Fields the service does
    not return are empty. Coordinates are always written with a period as the decimal
    separator, whatever the display language. Changes nothing.

.PARAMETER TimeoutSeconds
    How long to wait for a position, 1 to 600 seconds. Default 30.

.EXAMPLE
    .\GetLocation.ps1

    Outputs the address, rounded coordinates and public IP of the computer.

.NOTES
    Requires Windows 10 or later with location services on and allowed for desktop
    apps, and network access to ifconfig.me and nominatim.openstreetmap.org (the exact
    coordinates are sent to Nominatim). Runs on Windows PowerShell 5.1 and PowerShell 7;
    it does not use System.Device, which PowerShell 7 does not have, and does not start
    another PowerShell. No admin rights needed.
#>
[CmdletBinding()]
param (
    [ValidateRange(1, 600)]
    [int]$TimeoutSeconds = 30
)

function Initialize-GeolocatorInterop {
    <#
    .SYNOPSIS
        Compiles the C# helper that calls the Windows Runtime Geolocator, once per session.

    .DESCRIPTION
        The helper activates Windows.Devices.Geolocation.Geolocator with RoActivateInstance
        and calls its ABI methods through their vtable slots, so it needs neither the .NET
        Framework WinRT projection (gone in PowerShell 7) nor the C#/WinRT projection
        assemblies (not shipped with PowerShell). The same code compiles under Windows
        PowerShell 5.1 and PowerShell 7.
    #>
    [CmdletBinding()]
    param ()
    if ('PsuGeolocation.WinRtGeolocator' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Threading;

namespace PsuGeolocation
{
    public static class WinRtGeolocator
    {
        [DllImport("combase.dll")]
        private static extern int RoInitialize(int initType);
        [DllImport("combase.dll")]
        private static extern void RoUninitialize();
        [DllImport("combase.dll")]
        private static extern int RoActivateInstance(IntPtr activatableClassId, out IntPtr instance);
        [DllImport("combase.dll", CharSet = CharSet.Unicode)]
        private static extern int WindowsCreateString(string sourceString, int length, out IntPtr hstring);
        [DllImport("combase.dll")]
        private static extern int WindowsDeleteString(IntPtr hstring);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int QueryInterfaceMethod(IntPtr self, ref Guid iid, out IntPtr value);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetPointerMethod(IntPtr self, out IntPtr value);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetInt32Method(IntPtr self, out int value);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetDoubleMethod(IntPtr self, out double value);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetPositionMethod(IntPtr self, long maximumAge, long timeout, out IntPtr operation);
        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int CancelMethod(IntPtr self);

        private static readonly Guid IidGeolocator = new Guid("A9C3BF62-4524-4989-8AA9-DE019D2E551F");
        private static readonly Guid IidAsyncInfo = new Guid("00000036-0000-0000-C000-000000000046");
        private const int AccessDenied = unchecked((int)0x80070005);

        // Vtable slots: 0-2 IUnknown, 3-5 IInspectable, then each interface's own methods in order.
        private const int GeolocatorGetLocationStatus = 12;
        private const int GeolocatorGetPositionWithAgeAndTimeout = 14;
        private const int AsyncInfoGetStatus = 7;
        private const int AsyncInfoGetErrorCode = 8;
        private const int AsyncInfoCancel = 9;
        private const int AsyncOperationGetResults = 8;
        private const int GeopositionGetCoordinate = 6;
        private const int GeocoordinateGetLatitude = 6;
        private const int GeocoordinateGetLongitude = 7;

        private static T Slot<T>(IntPtr instance, int index) where T : class
        {
            IntPtr vtable = Marshal.ReadIntPtr(instance);
            IntPtr method = Marshal.ReadIntPtr(vtable, index * IntPtr.Size);
            return Marshal.GetDelegateForFunctionPointer(method, typeof(T)) as T;
        }

        private static void Check(int hr, string step)
        {
            if (hr >= 0) { return; }
            if (hr == AccessDenied)
            {
                throw new UnauthorizedAccessException("Access to location is denied. Turn on location services and allow desktop apps to access your location.");
            }
            throw new InvalidOperationException(string.Format("{0} failed with HRESULT 0x{1:X8}.", step, hr), Marshal.GetExceptionForHR(hr));
        }

        // IUnknown::QueryInterface through slot 0. Marshal.QueryInterface takes the IID by
        // ref on .NET Framework and by in on .NET 7+, so one call cannot compile on both.
        private static IntPtr QueryInterface(IntPtr instance, Guid iid, string step)
        {
            IntPtr result;
            Check(Slot<QueryInterfaceMethod>(instance, 0)(instance, ref iid, out result), step);
            return result;
        }

        private static void Release(IntPtr instance)
        {
            if (instance != IntPtr.Zero) { Marshal.Release(instance); }
        }

        // Activates the Geolocator and returns its IGeolocator pointer. className and
        // inspectable are set as soon as they exist, so the caller can free them in finally.
        private static IntPtr ActivateGeolocator(out IntPtr className, out IntPtr inspectable)
        {
            className = IntPtr.Zero;
            inspectable = IntPtr.Zero;
            const string ClassName = "Windows.Devices.Geolocation.Geolocator";
            Check(WindowsCreateString(ClassName, ClassName.Length, out className), "WindowsCreateString");
            Check(RoActivateInstance(className, out inspectable), "Activating the Geolocator");
            return QueryInterface(inspectable, IidGeolocator, "QueryInterface(IGeolocator)");
        }

        // Returns Geolocator.LocationStatus (PositionStatus 0-5) without asking for a position.
        // It reads no location data, so tests can call it to check the IID and vtable layout.
        public static int GetLocationStatus()
        {
            int initHr = RoInitialize(1);
            IntPtr className = IntPtr.Zero, inspectable = IntPtr.Zero, locator = IntPtr.Zero;
            try
            {
                locator = ActivateGeolocator(out className, out inspectable);
                int status;
                Check(Slot<GetInt32Method>(locator, GeolocatorGetLocationStatus)(locator, out status), "Geolocator.LocationStatus");
                return status;
            }
            finally
            {
                Release(locator);
                Release(inspectable);
                if (className != IntPtr.Zero) { WindowsDeleteString(className); }
                if (initHr >= 0) { RoUninitialize(); }
            }
        }

        // Returns { latitude, longitude } in degrees, or throws.
        public static double[] GetPosition(int timeoutSeconds)
        {
            if (timeoutSeconds < 1) { throw new ArgumentOutOfRangeException("timeoutSeconds"); }
            int initHr = RoInitialize(1);
            IntPtr className = IntPtr.Zero, inspectable = IntPtr.Zero, locator = IntPtr.Zero;
            IntPtr operation = IntPtr.Zero, info = IntPtr.Zero, position = IntPtr.Zero, coordinate = IntPtr.Zero;
            try
            {
                locator = ActivateGeolocator(out className, out inspectable);

                // TimeSpan in the WinRT ABI is a 64-bit count of 100 ns ticks.
                long maximumAge = TimeSpan.FromMinutes(1).Ticks;
                long timeout = TimeSpan.FromSeconds(timeoutSeconds).Ticks;
                Check(Slot<GetPositionMethod>(locator, GeolocatorGetPositionWithAgeAndTimeout)(locator, maximumAge, timeout, out operation), "GetGeopositionAsync");

                info = QueryInterface(operation, IidAsyncInfo, "QueryInterface(IAsyncInfo)");
                // The WinRT timeout and this deadline are the same, so -TimeoutSeconds bounds the wait.
                DateTime deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);
                int status;
                while (true)
                {
                    Check(Slot<GetInt32Method>(info, AsyncInfoGetStatus)(info, out status), "IAsyncInfo.Status");
                    if (status != 0) { break; }
                    if (DateTime.UtcNow > deadline)
                    {
                        Slot<CancelMethod>(info, AsyncInfoCancel)(info);
                        throw new TimeoutException(string.Format("The location service gave no position within {0} seconds.", timeoutSeconds));
                    }
                    Thread.Sleep(100);
                }
                if (status == 2) { throw new OperationCanceledException("The location request was canceled."); }
                if (status == 3)
                {
                    int error;
                    Check(Slot<GetInt32Method>(info, AsyncInfoGetErrorCode)(info, out error), "IAsyncInfo.ErrorCode");
                    Check(error, "GetGeopositionAsync");
                    throw new InvalidOperationException("The location request failed with no error code.");
                }

                Check(Slot<GetPointerMethod>(operation, AsyncOperationGetResults)(operation, out position), "GetResults");
                if (position == IntPtr.Zero) { throw new InvalidOperationException("The location service returned no position."); }
                Check(Slot<GetPointerMethod>(position, GeopositionGetCoordinate)(position, out coordinate), "Geoposition.Coordinate");
                if (coordinate == IntPtr.Zero) { throw new InvalidOperationException("The location service returned no coordinate."); }
                double latitude, longitude;
                Check(Slot<GetDoubleMethod>(coordinate, GeocoordinateGetLatitude)(coordinate, out latitude), "Geocoordinate.Latitude");
                Check(Slot<GetDoubleMethod>(coordinate, GeocoordinateGetLongitude)(coordinate, out longitude), "Geocoordinate.Longitude");
                return new double[] { latitude, longitude };
            }
            finally
            {
                Release(coordinate);
                Release(position);
                Release(info);
                Release(operation);
                Release(locator);
                Release(inspectable);
                if (className != IntPtr.Zero) { WindowsDeleteString(className); }
                if (initHr >= 0) { RoUninitialize(); }
            }
        }
    }
}
'@
}

function Invoke-GeolocatorRequest {
    <#
    .SYNOPSIS
        Returns the latitude, then the longitude, from the Windows Runtime Geolocator, or throws.

    .PARAMETER TimeoutSeconds
        How long to wait for a position.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param (
        [Parameter(Mandatory)]
        [int]$TimeoutSeconds
    )
    Initialize-GeolocatorInterop
    $Geolocator = 'PsuGeolocation.WinRtGeolocator' -as [type]
    $Geolocator::GetPosition($TimeoutSeconds)
}

function Get-DeviceCoordinate {
    <#
    .SYNOPSIS
        Returns the device latitude and longitude, or a terminating error when location is unavailable or denied.

    .PARAMETER TimeoutSeconds
        How long to wait for a position.
    #>
    [CmdletBinding()]
    param (
        [ValidateRange(1, 600)]
        [int]$TimeoutSeconds = 30
    )
    try {
        $Position = Invoke-GeolocatorRequest -TimeoutSeconds $TimeoutSeconds
    }
    catch {
        # A .NET method call wraps its exception in MethodInvocationException; report the real one.
        $Reason = $_.Exception
        if ($Reason -is [System.Management.Automation.MethodInvocationException] -and $Reason.InnerException) {
            $Reason = $Reason.InnerException
        }
        throw "Location is unavailable: $($Reason.Message)"
    }

    $Position = @($Position)
    $Valid = $Position.Count -eq 2 -and
        -not [double]::IsNaN($Position[0]) -and -not [double]::IsNaN($Position[1]) -and
        [math]::Abs($Position[0]) -le 90 -and [math]::Abs($Position[1]) -le 180
    if (-not $Valid) {
        throw "Location is unavailable: the location service returned no valid coordinates ($($Position -join ', '))."
    }
    [pscustomobject]@{
        Latitude  = [double]$Position[0]
        Longitude = [double]$Position[1]
    }
}

function Get-DeviceLocationReport {
    <#
    .SYNOPSIS
        Builds the <Road>|<City>|<State>|<CountryCode>|<Latitude>|<Longitude>|<PublicIP> line.

    .PARAMETER TimeoutSeconds
        How long to wait for a position.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [ValidateRange(1, 600)]
        [int]$TimeoutSeconds = 30
    )
    $Coordinate = Get-DeviceCoordinate -TimeoutSeconds $TimeoutSeconds
    # Invariant culture, so a comma decimal separator never reaches the URL or the output.
    $Invariant = [System.Globalization.CultureInfo]::InvariantCulture
    $Lat = $Coordinate.Latitude.ToString('R', $Invariant)
    $Long = $Coordinate.Longitude.ToString('R', $Invariant)
    $RoundLat = [math]::Round($Coordinate.Latitude, 2).ToString($Invariant)
    $RoundLong = [math]::Round($Coordinate.Longitude, 2).ToString($Invariant)
    $PubIP = Invoke-RestMethod -Uri 'http://ifconfig.me/ip' -ErrorAction Stop
    $Location = Invoke-RestMethod -Uri "https://nominatim.openstreetmap.org/reverse?lat=$Lat&lon=$Long&format=jsonv2&addressdetails=1" -ErrorAction Stop
    "$($Location.address.road)|$($Location.address.city)|$($Location.address.state)|$($Location.address.country_code)|$RoundLat|$RoundLong|$PubIP"
}

Get-DeviceLocationReport -TimeoutSeconds $TimeoutSeconds
