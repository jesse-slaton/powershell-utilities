# Thin wrappers around external tools. Every native command in StorageHealth goes through
# these functions so tests can mock them and so a failure is reported in one place.

function Invoke-VssAdmin {
    <#
    .SYNOPSIS
        Runs vssadmin.exe with the given arguments and returns its output.

    .DESCRIPTION
        Runs vssadmin.exe from PATH and returns its output lines. A non-zero exit code, or an
        output line that starts with "Error:" (Microsoft does not document vssadmin's exit
        codes), writes a non-terminating error that includes the arguments and the output.
        Private to StorageHealth.

    .PARAMETER ArgumentList
        The arguments passed to vssadmin.exe, one per element.

    .EXAMPLE
        Invoke-VssAdmin -ArgumentList 'list', 'shadowstorage'

        Returns the shadow storage associations of every volume.

    .EXAMPLE
        Invoke-VssAdmin -ArgumentList 'resize', 'ShadowStorage', '/For=C:', '/On=C:', '/MaxSize=10%'

        Caps the shadow storage of C: at 10 percent of the drive.

    .NOTES
        Windows only. Most vssadmin commands require administrator rights.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList
    )

    $output = @(& vssadmin @ArgumentList)
    # vssadmin exit codes are undocumented, so an "Error:" line also counts as failure.
    if ($LASTEXITCODE -ne 0 -or @($output -match '^\s*Error:').Count -gt 0) {
        Write-Error -Message ("vssadmin.exe {0} failed with exit code {1}: {2}" -f ($ArgumentList -join ' '), $LASTEXITCODE, ($output -join ' '))
        return
    }
    $output
}

function Invoke-Smartctl {
    <#
    .SYNOPSIS
        Runs smartctl -A for one device and returns its output.

    .DESCRIPTION
        Runs smartctl (smartmontools) from PATH with -A and the device, and returns its
        output lines. smartctl's exit code is a bit mask: bits 0 and 1 (bad command line,
        device could not be opened) write a non-terminating error; the other bits report
        disk state, not a failure to read it, so they are ignored. Private to StorageHealth.

    .PARAMETER Device
        The device to read, such as C: or /dev/sda.

    .EXAMPLE
        Invoke-Smartctl -Device 'C:'

        Returns the SMART attribute table of the disk that holds C:.

    .EXAMPLE
        Invoke-Smartctl -Device '/dev/sda'

        Returns the SMART attribute table of the first disk, named the smartmontools way.

    .NOTES
        Requires smartctl on PATH and, normally, administrator rights.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Device
    )

    $output = @(& smartctl -A $Device)
    if ($LASTEXITCODE -band 3) {
        Write-Error -Message ("smartctl -A {0} failed with exit code {1}: {2}" -f $Device, $LASTEXITCODE, ($output -join ' '))
        return
    }
    $output
}

function ConvertFrom-SmartVendorSpecific {
    <#
    .SYNOPSIS
        Parses the VendorSpecific bytes of MSStorageDriver_FailurePredictData into SMART attributes.

    .DESCRIPTION
        The buffer holds a 2-byte revision and then 30 attribute records of 12 bytes each:
        attribute ID, two status flag bytes, the normalized value, the worst value, six raw
        bytes and a reserved byte. Returns one object per record whose attribute ID is not
        zero (unused slots are zero), with AttrID, StatusFlag1, StatusFlag2, AttrValue,
        WorstValue, Raws (the six raw bytes) and Reserved. Bytes past the 30th record are
        not attributes and are ignored. Private to StorageHealth.

    .PARAMETER VendorSpecific
        The VendorSpecific byte array (normally 512 bytes).

    .EXAMPLE
        ConvertFrom-SmartVendorSpecific -VendorSpecific $smart.VendorSpecific

        Returns the attribute records of one MSStorageDriver_FailurePredictData instance.

    .EXAMPLE
        ConvertFrom-SmartVendorSpecific -VendorSpecific $smart.VendorSpecific | Where-Object AttrID -eq 5

        Returns only the reallocated sectors record.

    .NOTES
        None.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowEmptyCollection()]
        [byte[]]$VendorSpecific = @()
    )

    for ($slot = 0; $slot -lt 30; $slot++) {
        $i = 2 + $slot * 12
        if ($i + 12 -gt $VendorSpecific.Length) { break }
        if ($VendorSpecific[$i] -eq 0) { continue }
        [pscustomobject]@{
            AttrID      = $VendorSpecific[$i]
            StatusFlag1 = $VendorSpecific[$i + 1]
            StatusFlag2 = $VendorSpecific[$i + 2]
            AttrValue   = $VendorSpecific[$i + 3]
            WorstValue  = $VendorSpecific[$i + 4]
            Raws        = $VendorSpecific[($i + 5)..($i + 10)]
            Reserved    = $VendorSpecific[$i + 11]
        }
    }
}

function Test-IsAdministrator {
    <#
    .SYNOPSIS
        Returns $true when the current session runs elevated as an administrator.

    .DESCRIPTION
        Checks the current Windows identity for the built-in Administrators role. Private to
        StorageHealth.

    .EXAMPLE
        if (-not (Test-IsAdministrator)) { throw 'Run as administrator.' }

    .NOTES
        Windows only.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $principal = New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList ([Security.Principal.WindowsIdentity]::GetCurrent())
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
