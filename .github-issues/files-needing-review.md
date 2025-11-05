# Files Needing Review - Unclear Purpose or Legacy Code

## Description
Several scripts have unclear purposes, non-descriptive names, or appear to be legacy/one-time-use scripts that should be reviewed for potential archival or better documentation.

## Files to Review

### Scripts/General/

1. **move_win10.ps1**
   - **Issue**: Non-descriptive name, lowercase, underscores
   - **Content**: Moves specific list of 266 hardcoded computer names to Windows 10 staging OU
   - **Recommendation**: Appears to be one-time migration script. Move to `Archive/` or delete. If kept, rename to `Move-ComputersToWin10StagingOU.ps1`

2. **StuffedScopeArray.ps1**
   - **Issue**: Non-descriptive name
   - **Content**: Looks up computer location based on network subnet from CSV file
   - **Recommendation**: Rename to `Get-ComputerLocationFromSubnet.ps1` or `Get-NetworkScopeLocation.ps1`

3. **PSObjectBrowser.ps1**
   - **Issue**: File size is 269KB (extremely large for a single script)
   - **Content**: Unable to read due to size
   - **Recommendation**: Review if this is actually needed, consider breaking into module

4. **ncsidiag-Package.ps1**
   - **Issue**: Abbreviation not immediately clear
   - **Content**: Network Connectivity Status Indicator diagnostics
   - **Recommendation**: Rename to `Get-NetworkConnectivityStatus-Package.ps1` or `Test-NCSIDiagnostics-Package.ps1`

5. **get-indexedItem.ps1**
   - **Issue**: Lowercase verb (non-standard PowerShell naming)
   - **Content**: Function to search Windows Search index
   - **Recommendation**: Rename to `Get-IndexedItem.ps1` (capitalize G)

### Scripts/Office/

6. **ChangeOLP.ps1**
   - **Issue**: Abbreviation "OLP" not immediately obvious
   - **Content**: Office Language Pack installer GUI
   - **Recommendation**: Rename to `Install-Office365LanguagePack.ps1` or `Set-Office365LanguagePack.ps1`

### Scripts/Application/

7. **StartSMC.ps1**
   - **Issue**: Abbreviation "SMC" not clear
   - **Content**: Starts Symantec Management Client (Endpoint Protection)
   - **Recommendation**: Rename to `Start-SymantecManagementClient.ps1`

8. **stopSMC.ps1**
   - **Issue**: Lowercase verb, abbreviation not clear
   - **Content**: Stops Symantec Management Client
   - **Recommendation**: Rename to `Stop-SymantecManagementClient.ps1`

### Scripts/System/

9. **TestSSD.ps1**
   - **Issue**: Missing verb-noun separator (hyphen)
   - **Content**: Tests if drive is SSD
   - **Recommendation**: Rename to `Test-SolidStateDrive.ps1` or `Test-IsSSD.ps1`

10. **DetectSSD.ps1**
    - **Issue**: Non-standard verb (should be Test/Get), missing hyphen
    - **Content**: Detects if drive is SSD
    - **Recommendation**: Rename to `Get-SolidStateDrive.ps1` or merge with TestSSD

### Scripts/Network/

11. **multipleips.ps1**
    - **Issue**: Lowercase, no verb-noun format, unclear name
    - **Content**: Not yet reviewed
    - **Recommendation**: Review and rename with proper verb-noun format

12. **CHG0000000_DisableNetBiosOverTCPIP.ps1**
    - **Issue**: Contains change ticket number (CHG#) - superfluous detail
    - **Content**: Disables NetBIOS over TCP/IP
    - **Recommendation**: Rename to `Disable-NetBiosOverTcpIp.ps1` or `Disable-NetBiosOverTcpIp-Package.ps1`

### Files with `.psm1-Package.ps1` extension (Non-standard)

13. **AdobeReader.psm1-Package.ps1**
14. **Chrome.psm1-Package.ps1**
15. **GroupPolicy.psm1-Package.ps1**
16. **Compliance.psm1-Package.ps1**
    - **Issue**: Unusual double extension (should be either .psm1 or .ps1, not both)
    - **Recommendation**: Determine if these should be modules (.psm1) or scripts (.ps1). If scripts, rename to standard `-Package.ps1` suffix

### Files with underscores instead of hyphens

17. **Find-WMIPigs_nodelay.ps1**
    - Rename to `Find-WMIPigs-NoDelay.ps1` or add as parameter
18. **Get-AttachedMonitorInfo_-Sensor.ps1**
    - Rename to `Get-AttachedMonitorInfo-Sensor.ps1` (remove underscore)
19. **Get-8021x_Profiles.ps1**
    - Rename to `Get-8021xProfile.ps1` or `Get-WiredAuthenticationProfile.ps1`
20. **Get_EFSStatus.ps1**
    - Rename to `Get-EFSStatus.ps1`
21. **Remove_All_Versions_***.ps1** (multiple files)
    - Rename with hyphens instead of underscores
22. **Create_ms-msdt_Key.ps1**
    - Rename to `New-MsMsdtRegistryKey.ps1` or similar

### Files with spaces in names

23. **AD Query - *** .ps1** (multiple files)
    - Consider prefixing with `Get-` or keeping as-is if they're related queries
24. **Uninstall OneDrive-Package.ps1**
    - Rename to `Uninstall-OneDrive-Package.ps1`
25. **Protect Privacy-Package.ps1**
    - Rename to appropriate verb-noun format like `Set-PrivacySettings-Package.ps1`

## Action Items

- [ ] Review each file's purpose and determine if it should be kept
- [ ] Move legacy/one-time scripts to `Archive/Legacy/` directory
- [ ] Rename files to follow PowerShell naming conventions
- [ ] Update any scripts that reference renamed files
- [ ] Update test files to match new names
- [ ] Update documentation files to match new names
- [ ] Create proper help documentation for unclear scripts

## Notes

**✅ Confirmed: No *arr (Radarr, Sonarr, etc.) or Emby scripts found in repository**
