# Archived scripts

Scripts removed from `main` because the product they depend on is no longer in use.
They are kept in git history: restore one with
`git show 38099f6cd88a:"<path>" > "<file>"`, or browse
https://github.com/jesse-slaton/powershell-utilities/tree/38099f6cd88a.

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
