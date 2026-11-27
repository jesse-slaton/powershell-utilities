# Archived scripts

Scripts removed from `main` because the product they depend on is no longer in use,
because the workaround they provide is no longer needed, because they cannot run as written,
or because a module function now does their job. Each section says which. They are kept in
git history: restore one with `git show <commit>:"<path>" > "<file>"`, using the last commit
listed in its section, or browse
`https://github.com/jesse-slaton/powershell-utilities/tree/<commit>`.

Third-party code that was removed is listed with its upstream in
[EXTERNAL_REPOS.txt](./EXTERNAL_REPOS.txt).

## Altiris agent scripts (#51, 2026-11)

Every script here needs the Altiris (Symantec ITMS) agent's COM classes or WMI class,
and the agent is no longer deployed. Last commit that has them: `38099f6cd88a`.

| Path | What it did |
|---|---|
| `Scripts/ActiveDirectory/AD Query - Altiris Primary User Details.ps1` | Outputs Active Directory details for the Altiris primary user of this computer. |
| `Scripts/ActiveDirectory/AD Query - Altiris Primary User Group Member.ps1` | Reports whether the Altiris primary user of this computer is in a matching AD group. |
| `Scripts/ActiveDirectory/AD Query - Altiris Primary User Manager.ps1` | Reports whether the manager of the Altiris primary user matches a given name. |
| `Scripts/ActiveDirectory/ResetPrimaryAltirisUser.ps1` | Clears the Altiris Agent's recorded primary user and sends a new basic inventory. |
| `Scripts/General/Get-ShellFolderInfo.ps1` | Deletes shortcuts to Avaya CMS Supervisor versions other than R18 for the primary user and all users. |
| `Scripts/Network/RSoP-WiredLANPolicy.ps1` | Reports which wired (802.3) Group Policy objects apply to this computer to the Altiris Notification Server as custom inventory. |
| `Scripts/System/Altiris-COMObjects.ps1` | Creates an instance of each Altiris agent COM class and stores it in a variable. |
| `Scripts/System/Set-MIGPathOwner.ps1` | Makes the Altiris primary user the owner of C:\MIG and grants that user Full Control. |

## Scripts with a missing dependency (#120, 2026-11)

These scripts import a module that is not in this repository and never was, so they
cannot run. Last commit that has them: `293649f0ab13`.

| Path | What it did |
|---|---|
| `Scripts/System/MainCleanupScript.ps1` | Ran recycle bin, temporary file, DISM and CCM cache cleanup as a timed background job. Every cleanup step lived in `CleanupFunctions.psm1`, which was never committed, and no copy survives outside the repo either (a search of the original Windows machine found none), so the script cannot be ported. |

## Superseded by the OfficeC2R module (#45, 2026-11)

These scripts did the same job as a function in `Modules/OfficeC2R`, so they were removed
rather than ported. Last commit that has them: `741cebd003d0`.

| Path | What it did | Use instead |
|---|---|---|
| `Scripts/Office/GetOffice365Channel-Package.ps1` | Output the Office Click-to-Run update channel name from CDNBaseUrl, relaunching itself in 64-bit Windows PowerShell when started from 32-bit PowerShell. | `Get-OfficeC2RChannel`, which reads the 64-bit registry view directly and also knows DevMain Channel. |

## Retired with the SecurityPosture module (#46, 2026-11)

These scripts were not ported to `Modules/SecurityPosture`: one did nothing, the other
wrapped a program that is not in this repository. Last commit that has them: `b57268c28050`.

| Path | What it did | Use instead |
|---|---|---|
| `Scripts/Security/GetBitlockerProtectionStatus.ps1` | Ran an in-house BitlockerProtection.exe (not in this repository) from the current directory and appended its output, with a timestamp, to BitlockerStatus.csv. | `Get-BitLockerVolumeStatus` in `Modules/SecurityPosture`, which reads BitLocker volume state through CIM. |
| `Scripts/Security/TestDeviceGuardStatus.ps1` | Read Win32_DeviceGuard and defined lookup tables, but wrote no output. | `Get-DeviceGuardStatus` and `Get-DeviceGuardSecurityProperty` in `Modules/SecurityPosture`. |

## Obsolete Chrome workarounds (#44, 2026-11)

One-off workarounds for old Google Chrome builds, retired instead of being folded into the
`ChromeProfile` module. Last commit that has them: `65206d766586`.

| Path | What it did |
|---|---|
| `Scripts/General/Create-ChromeTestShortcut.ps1` | Created a "Test Chrome" Desktop shortcut that starts the 32-bit (x86) Chrome install with the audio service sandbox disabled. |
| `Scripts/General/Fix-Chrome77JumpList.ps1` | Copied Chrome's jump list file so a pinned Chrome taskbar icon shows its jump list again after the Chrome 77 change. |

## Retired with the StorageHealth module (#47, 2026-11)

This script was not ported to `Modules/StorageHealth`: it compiled the SSD checks but never
ran them, and `Test-SSD` now runs the same checks. Last commit that has it: `278a9a725d8e`.

| Path | What it did | Use instead |
|---|---|---|
| `Scripts/System/DetectSSD.ps1` | Compiled a C# class with a seek-penalty and a rotation-rate SSD check, but never called either. | `Test-SSD` in `Modules/StorageHealth`, which runs both checks (it replaces `Scripts/System/TestSSD.ps1`). |

## Retired scripts (#134, 2026-11)

These scripts were retired because the product or workaround they served is gone, or because
they cannot run as written. Last commit that has them: `7d81d42125ed`.

| Path | What it did |
|---|---|
| `Scripts/ActiveDirectory/GetLastUserDetails-Package.ps1` | Tried to report the most recent logon and elapsed time per user; the output line could not be produced and the per-user logic never worked. |
| `Scripts/ActiveDirectory/Test-InteractiveLogonUser.ps1` | Defined a function that inferred an interactive logon from the explorer process; it called an undefined Test-Process command, so it could not run anywhere. |
| `Scripts/Application/Remove-IntelDCHDriver.ps1` | One-time migration that removed legacy Intel display devices and their driver packages for the DCH driver move; depended on a devcon.exe that is not shipped. |
| `Scripts/Application/StartSMC.ps1` | Started the Symantec Endpoint Protection client through smc.exe (obsolete product). |
| `Scripts/Application/stopSMC.ps1` | Disabled and stopped the Symantec Endpoint Protection client through smc.exe (obsolete product; companion of StartSMC.ps1). |
| `Scripts/Development/Test-AAfDConfigFile.ps1` | Compared a contact-center agent config file to a hard-coded expected hash for one internal deployment. |
| `Scripts/Utilities/RecieverCleanupUtilityWrapper.ps1` | Unfinished stub for a Citrix Receiver clean-up (obsolete product, replaced by Workspace app). |

## Retired scripts (#135, 2026-11)

These scripts were retired because they cannot deliver their purpose as written, because a
near-duplicate supersedes them, or because the product they targeted is gone. Last commit that
has them: `62aa6bae2a98`.

| Path | What it did |
|---|---|
| `Scripts/FileSystem/FindPSTFiles-Package.ps1` | Tried to list .pst files on local drives as JSON; the list was wrong (one file per drive, empty path field). |
| `Scripts/Utilities/FindPSTSensor.ps1` | Printed the PST inventory JSON as pipe-delimited lines; its only input came from FindPSTFiles-Package.ps1, so it read a file nothing produces. |
| `Scripts/FileSystem/Get-8021x_Profiles.ps1` | Parsed netsh lan profiles and printed the first profile's 802.1X settings; a near-duplicate of Get-WiredLANProfile.ps1, which uses the same parser and also reports and starts the dot3svc service. |
| `Scripts/FileSystem/getVPNProfileReady-Sensor.ps1` | Sensor that reported ready when the IP Helper service was automatic and running and a VPN client profile flag was set; the profile half of the check was a no-op. |
| `Scripts/FileSystem/Set-AnyConnectLocalProxy.ps1` | Set AllowLocalProxyConnections in the profile XMLs of a 4.x VPN client (obsolete product; the profile folder moved in the 5.x release, so the path no longer exists). |
| `Scripts/FileSystem/Uninstall OneDrive-Package.ps1` | Uninstalled OneDrive from the Windows 10 inbox installer locations and removed its folders (obsolete product; the explorer stop step never worked). |

## Retired scripts (#136, 2026-11)

These scripts were retired because a near-duplicate supersedes them, because they cannot run as
written, or because the product they targeted is gone. Last commit that has them: `05bd0b1caecf`.

| Path | What it did |
|---|---|
| `Scripts/General/GetExplorerArch-Package.ps1` | Reported whether one hard-coded browser was 32-bit or 64-bit; a misnamed near-duplicate of the kept binary-type sensor, which takes the target as a parameter. |
| `Scripts/General/ArchTest-Package.ps1` | Template stub whose only real logic was a relaunch pinned to Windows PowerShell 5.1; the body was a placeholder. |
| `Scripts/General/Find-Hack-Run-Sensor.ps1` | Listed a suspicious file name and hash in users' legacy browser cache folder (obsolete product, that browser is retired). |
| `Scripts/General/GetBetaVersions.ps1` | Unfinished stub that parsed a release-history page with an unmaintained third-party library loaded from a personal hard-coded path; it produced no output. |

## Retired scripts (#137, 2026-11)

These scripts were retired because they were one-time migrations, because the product they
targeted is obsolete, or because they were unfinished demos. Last commit that has them:
`dff278add585`.

| Path | What it did |
|---|---|
| `Scripts/General/move_win10.ps1` | Moved a hard-coded list of computers into a staging OU for a past Windows 10 rollout (one-time migration). |
| `Scripts/General/Test-MIAVC-Sensor.ps1` | Compared the installed VPN client version to a reference; hard-coded to one VPN client's 4.7 version (obsolete product, renamed since) and the comparison never matched. |
| `Scripts/General/test-UIforPS7.ps1` | Throwaway demo window with a button that filled a text box; incomplete, with no function, and it depended on an unmaintained third-party UI toolkit. |

## Retired scripts (#138, 2026-11)

These scripts were retired because they were org-specific, because they cannot run as written,
or because the product they targeted is obsolete. Last commit that has them: `4d4706693435`.

| Path | What it did |
|---|---|
| `Scripts/General/Create-PAXInstallShortCut.ps1` | Created a Desktop shortcut to an internally staged installer under a hard-coded support-tools folder (org-specific). |
| `Scripts/General/Import-WindowsErrorCode.ps1` | Scraped Windows error codes from a retired documentation site into objects; it depended on removed DOM parsing and on that site's old page layouts. Get-WindowsErrorCodeInfo.ps1 covers the lookup use and stays. |
| `Scripts/General/Set-URLInfoAbout-Package.ps1` | Rewrote uninstall-entry support links to one endpoint product's 8.5 documentation (obsolete product, org-specific deployment tweak). |
| `Scripts/General/Show-ProcessTree-Sensor.ps1` | Unfinished sensor meant to print a process tree; a read-only `$pid` assignment and a broken filter made its output unusable. |
| `Scripts/General/StuffedScopeArray.ps1` | Sensor mapping the primary adapter's subnet to a location using an internally staged location file under a hard-coded support-tools folder (org-specific). |

## Retired scripts (#139, 2026-11)

These scripts were retired because the products or features they targeted are obsolete, or
because they were broken. Last commit that has them: `14ab2eda3e19`.

| Path | What it did |
|---|---|
| `Scripts/Network/Debloat Windows.ps1` | Removed AppX packages named in a Windows 10 era sponsored-app list and purged everything outside an allowlist (obsolete product, destructive). |
| `Scripts/Network/Disable Cortana.ps1` | Set per-user registry values to disable a discontinued assistant (obsolete product). |
| `Scripts/Network/Enable Cortana.ps1` | Set per-user registry values to enable a discontinued assistant (obsolete product). |
| `Scripts/Network/Enable Edge PDF.ps1` | Removed .pdf NoOpenWith values for the legacy browser engine's AppX ProgID; the key-rename logic was broken (obsolete product). |
| `Scripts/Network/Stop Edge PDF.ps1` | Added .pdf NoOpenWith values for the legacy browser engine's AppX ProgID; the key-rename logic was broken (obsolete product). |
| `Scripts/Network/Protect Privacy-Package.ps1` | Applied a Windows 10 1709-era set of privacy tweaks to registry, tasks and services; now handled by policy (obsolete product). |
| `Scripts/Network/Revert Changes.ps1` | Partial undo of the retired debloat and privacy scripts (obsolete product). |
| `Scripts/Network/Fix Whitelisted Apps-Sensor.ps1` | Meant to re-register a few preinstalled apps, but its if test was never true on a normal system, so it did nothing; it also targeted a discontinued preinstalled app (broken/incomplete). |

## Retired scripts (#140, 2026-11)

These scripts were retired because they were broken or incomplete, superseded, one-time
migrations, or targeted an obsolete product. Last commit that has them: `6944d130da9e`.

| Path | What it did |
|---|---|
| `Scripts/Network/ExportandUploadApplicationCrashEvtxToS3Bucket.ps1` | Exported 7 days of application crash events and meant to upload them to a remote bucket; the zip step always failed, so nothing was ever uploaded (broken/incomplete, near-duplicate of the Security variant). |
| `Scripts/Network/ExportandUploadSecurityEvtxToS3Bucket.ps1` | Exported 7 days of the Security log and meant to upload it to a remote bucket; the zip step always failed, so nothing was ever uploaded (broken/incomplete, near-duplicate of the crash-event variant). |
| `Scripts/Network/WPRtoS3Upload.ps1` | Meant to install the recorder, record 5 minutes and upload the zip to a remote bucket; it never produced an ETL file (superseded by StartWPRSession-Sensor.ps1). |
| `Scripts/Network/TestRestoreScript.ps1` | Wrote a sample backup JSON for an external restore script that is not in this repository (orphan test fixture, broken/incomplete). |
| `Scripts/Network/Get-ScopeDetails-Sensor.ps1` | Collected active DHCP scopes and option 1 values, but wrote nothing to the pipeline despite its sensor name and hard-coded an internal server exclusion (broken/incomplete). |
| `Scripts/Network/Set-DhcpNetBiosOverTcpIpOption.ps1` | Set DHCP vendor option 1 on all servers to disable NetBIOS; a one-time fleet-wide migration with a hard-coded internal server exclusion. |
| `Scripts/Network/Remove Bloatware RegKeys.ps1` | Deleted leftover class-registration keys for specific preinstalled-app package versions pinned to a 2017-era release that no longer exists (obsolete product). |

## Retired scripts (#141, 2026-11)

These scripts were retired because they were broken or incomplete, one-time migrations, or
targeted an obsolete or organization-specific product. Last commit that has them: `2d5263d3e119`.

| Path | What it did |
|---|---|
| `Scripts/Office/Get-ProcessBitness-Sensor.ps1` | Defined a function to detect 32-bit and 64-bit processes, but depended on an undefined Test-Process helper and never ran as committed (broken/incomplete). |
| `Scripts/Office/MigrateOffice.ps1` | Built a deployment config and installed Office as 64-bit; a one-time migration from the MSI build to the click-to-run build and from 32-bit to 64-bit, with a hard-coded organization Company value. |
| `Scripts/Office/Set-OneBaseRetrievalButtonValue.ps1` | Edited a third-party document-management add-in's Office 2016 integration folder to disable one button (obsolete product, org-specific setting). |
| `Scripts/Security/Get_EFSStatus.ps1` | Started an EFS scan at idle priority but never captured its result (broken/incomplete). |
| `Scripts/Security/HylandCompliance-Package.ps1` | Checked components against pinned build numbers from one organization's 20.3 rollout (org-specific). |

## Retired scripts (#142, 2026-11)

These scripts were retired because they targeted an obsolete product. Last commit that has them: `c29f6bb7ba2a`.

| Path | What it did |
|---|---|
| `Scripts/Security/Get-BitlockerCompliance.ps1` | Joined a legacy client-management inventory database, directory data and disk-encryption recovery IDs into spreadsheet-ready CSVs; it depended on a third-party disk-encryption product and its columns had been frozen since 2019 (obsolete product). |
| `Tests/Unit/Get-BitlockerCompliance.Tests.ps1` | Unit tests that covered the retired compliance script. |
