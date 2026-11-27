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
