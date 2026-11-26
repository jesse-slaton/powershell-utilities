function Get-OfficeC2RBitness {
    <#
    .SYNOPSIS
        Outputs whether the installed Office Click-to-Run is 32-bit or 64-bit.

    .DESCRIPTION
        Reads Platform from HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration (64-bit
        registry view) and outputs "32-bit" for x86, "64-bit" for x64, or
        "Unknown Office Platform: <value>" for anything else.

        When the Configuration key does not exist (Office Click-to-Run is not installed) or
        Platform is not set, it writes a non-terminating error and outputs nothing. When the
        registry read itself fails (such as access denied), it writes that error, not a
        "not installed" one, and outputs nothing. Read-only.

        Replaces Scripts/Office/GetOffice365Bitness.ps1; its function name
        Get-OfficeClickToRunBitness is kept as an alias.

    .EXAMPLE
        Get-OfficeC2RBitness

        64-bit

    .EXAMPLE
        Get-OfficeClickToRunBitness -ErrorAction SilentlyContinue

        Uses the old function name; outputs nothing when Office Click-to-Run is not installed.

    .NOTES
        None. Windows only. Reads HKLM without administrator rights. Only Click-to-Run
        installations are detected; MSI-based Office is reported as not found. Part of the
        OfficeC2R module.
    #>
    [CmdletBinding()]
    [Alias('Get-OfficeClickToRunBitness')]
    [OutputType([string])]
    param()

    try {
        $config = Get-OfficeC2RConfigurationValue -Name 'Platform' -ErrorAction Stop
    }
    catch {
        $PSCmdlet.WriteError($_)
        return
    }
    if ($null -eq $config) {
        Write-Error -Message 'Office Click-to-Run configuration is not found. Office may not be installed.' -Category ObjectNotFound
        return
    }

    $platform = [string]$config['Platform']
    switch ($platform) {
        '' { Write-Error -Message 'The Platform value is not set. Unable to determine Office bitness.' -Category ObjectNotFound }
        'x86' { '32-bit' }
        'x64' { '64-bit' }
        default { "Unknown Office Platform: $platform" }
    }
}
