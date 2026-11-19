<#
.SYNOPSIS
    Sets the current user's Cortana and input personalization registry values back to their enabled state.

.DESCRIPTION
    Creates these HKCU keys if they are missing and sets the following values:
    - HKCU:\SOFTWARE\Microsoft\Personalization\Settings: AcceptedPrivacyPolicy = 1
    - HKCU:\SOFTWARE\Microsoft\InputPersonalization: RestrictImplicitTextCollection = 0,
      RestrictImplicitInkCollection = 0
    - HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore: HarvestContacts = 1

    Writes "Re-enabling Cortana" to the host. New-Item writes the key object when it
    creates a key. This reverses Disable Cortana.ps1.

.EXAMPLE
    & '.\Enable Cortana.ps1'

    Applies the enabled values for the user running the script.

.NOTES
    No admin rights needed. Changes only the HKCU hive of the user who runs it, so run
    it in that user's context (not as SYSTEM). Works in Windows PowerShell 5.1 and
    PowerShell 7.
#>
Write-Host "Re-enabling Cortana"
    $Cortana1 = "HKCU:\SOFTWARE\Microsoft\Personalization\Settings"
    $Cortana2 = "HKCU:\SOFTWARE\Microsoft\InputPersonalization"
    $Cortana3 = "HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore"
	If (!(Test-Path $Cortana1)) {
		New-Item $Cortana1
	}
	Set-ItemProperty $Cortana1 AcceptedPrivacyPolicy -Value 1 
	If (!(Test-Path $Cortana2)) {
		New-Item $Cortana2
	}
	Set-ItemProperty $Cortana2 RestrictImplicitTextCollection -Value 0 
	Set-ItemProperty $Cortana2 RestrictImplicitInkCollection -Value 0 
	If (!(Test-Path $Cortana3)) {
		New-Item $Cortana3
	}
	Set-ItemProperty $Cortana3 HarvestContacts -Value 1 
