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
