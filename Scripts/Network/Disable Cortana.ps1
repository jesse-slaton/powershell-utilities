<#
.SYNOPSIS
    Sets the current user's Cortana and input personalization registry values to their disabled state.

.DESCRIPTION
    Creates these HKCU keys if they are missing and sets the following values:
    - HKCU:\SOFTWARE\Microsoft\Personalization\Settings: AcceptedPrivacyPolicy = 0
    - HKCU:\SOFTWARE\Microsoft\InputPersonalization: RestrictImplicitTextCollection = 1,
      RestrictImplicitInkCollection = 1
    - HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore: HarvestContacts = 0

    Writes "Disabling Cortana" to the host. New-Item writes the key object when it
    creates a key. Enable Cortana.ps1 sets the opposite values.

.EXAMPLE
    & '.\Disable Cortana.ps1'

    Applies the disabled values for the user running the script.

.NOTES
    No admin rights needed. Changes only the HKCU hive of the user who runs it, so run
    it in that user's context (not as SYSTEM). Works in Windows PowerShell 5.1 and
    PowerShell 7.
#>
Write-Host "Disabling Cortana"
    $Cortana1 = "HKCU:\SOFTWARE\Microsoft\Personalization\Settings"
    $Cortana2 = "HKCU:\SOFTWARE\Microsoft\InputPersonalization"
    $Cortana3 = "HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore"
	If (!(Test-Path $Cortana1)) {
		New-Item $Cortana1
	}
	Set-ItemProperty $Cortana1 AcceptedPrivacyPolicy -Value 0 
	If (!(Test-Path $Cortana2)) {
		New-Item $Cortana2
	}
	Set-ItemProperty $Cortana2 RestrictImplicitTextCollection -Value 1 
	Set-ItemProperty $Cortana2 RestrictImplicitInkCollection -Value 1 
	If (!(Test-Path $Cortana3)) {
		New-Item $Cortana3
	}
	Set-ItemProperty $Cortana3 HarvestContacts -Value 0
