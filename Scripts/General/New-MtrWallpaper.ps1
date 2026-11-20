<#
.SYNOPSIS
    Sets a random custom wallpaper on a Microsoft Teams Room (MTR) system by running
    New-MtrWallpaper once against the default LocalState folder.

.DESCRIPTION
    Defines New-MtrWallpaper and then calls it with no arguments, so running (or
    dot-sourcing) the script acts straight away on the LocalState folder of the Skype
    account's Microsoft.SkypeRoomSystem package (the ThisRoot default). In that folder it
    deletes any existing wallpaper.jpg and SkypeSettings.xml, picks a random .jpg from the
    Wallpapers subfolder, copies it to wallpaper.jpg and writes a SkypeSettings.xml that
    selects the Custom theme with that image. If Wallpapers holds no .jpg, the two files
    are still deleted and nothing new is written. The script writes no output.

.EXAMPLE
    .\New-MtrWallpaper.ps1

    Replaces the wallpaper files in the default LocalState folder; the MTR app applies the
    new theme at its next restart.

.NOTES
    Changes files on the MTR system: run it on the MTR itself as the Skype account or an
    administrator (write access to the LocalState folder is required). Images in
    Wallpapers must be exactly 3840x1080. To target another folder, paste the function
    into a session and call New-MtrWallpaper -ThisRoot <folder>; dot-sourcing the script
    first runs it against the default folder.
#>


function New-MtrWallpaper {
    <#
        .SYNOPSIS
        Configure a new wallpaper for Microsoft Teams Room (MTR) System
        .DESCRIPTION
        Configure a new wallpaper for Microsoft Teams Room (MTR) System. This is done by randomly choosing a .jpg file from a folder of images. Wallpaper is then copied to the proper folder, and a corresponding XML file is also written. When the system reboots as part of its normal scheduled nightly maintenance, the new wallpaper is set for the 'Custom' them in MTR.
        Any wallpaper.jpg and SkypeSettings.xml left in the folder are deleted first. If the Wallpapers subfolder holds no .jpg file, nothing new is written. The function returns no output. Running the script calls New-MtrWallpaper once with the default folder.
        .PARAMETER ThisRoot
        The MTR app LocalState folder. It must contain a Wallpapers subfolder of .jpg images; wallpaper.jpg and SkypeSettings.xml are written here. Defaults to the LocalState folder of the Skype account's Microsoft.SkypeRoomSystem package.
        .EXAMPLE
        New-MtrWallpaper
        Picks image, copies to folder, and writes XML file
        .EXAMPLE
        New-MtrWallpaper -ThisRoot 'D:\MtrStaging\LocalState' -Verbose
        Uses a different LocalState folder and reports the chosen image on the verbose stream. Paste the function into the session first: dot-sourcing the script also runs New-MtrWallpaper against the default folder.
        .NOTES
        Requires Windows on a Microsoft Teams Room system, and write access to ThisRoot (run as the Skype account or an administrator). Images in Wallpapers must be exactly 3840x1080. The new theme applies at the next reboot (normally the nightly maintenance restart).
        .LINK
        https://www.ucunleashed.com/4323
        .INPUTS
        None. This function does not support pipeline input.
        .OUTPUTS
        None.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
      [string] $ThisRoot = 'C:\Users\Skype\AppData\Local\Packages\Microsoft.SkypeRoomSystem_8wekyb3d8bbwe\LocalState'
    )
    # Let's clean up any remaining files (which shouldn't exist if last reboot successfully ingested the files)
    if (Get-Item -Path "$ThisRoot\wallpaper.jpg" -ErrorAction SilentlyContinue){Remove-Item -Path "$ThisRoot\wallpaper.jpg" -Force -Confirm:$false}
    if (Get-Item -Path "$ThisRoot\SkypeSettings.xml" -ErrorAction SilentlyContinue){Remove-Item -Path "$ThisRoot\SkypeSettings.xml" -Force -Confirm:$false}
    # Get a list of all of the wallpapers to choose from. Wallpaper images MUST be exactly 3840x1080, regardless if the MTR is a single or dual screen system.
    $AllWallpapers = (Get-ChildItem -Path "$ThisRoot\Wallpapers" -Filter *.jpg | Select-Object -Property Name)
    # Pick a random wallpaper - keep in mind that the fewer images to choose from, the higher the potential to choose the same image that was used last time.
    [string] $NewWallpaper = (Get-Random -InputObject $AllWallpapers).Name
    Write-Verbose -Message "Chosen wallpaper is $ThisRoot\Wallpapers\$NewWallpaper"
    if ($NewWallpaper) {
      # Copy the chosen wallpaper to the right folder. We rename it to a generic name as a safeguard against improper characters or file names that are too long.
      Copy-Item -Path "$ThisRoot\Wallpapers\$NewWallpaper" -Destination "$ThisRoot\wallpaper.jpg"
      # Create the new SkypeSettings.xml using only the fields we need to populate to configure the new wallpaper
      $xmlWriter = New-Object -TypeName System.XMl.XmlTextWriter -ArgumentList ("$ThisRoot\SkypeSettings.xml",$Null)
      $xmlWriter.Formatting = 'Indented'
      $xmlWriter.Indentation = 1
      $XmlWriter.IndentChar = "`t"
      $xmlWriter.WriteStartDocument()
      $xmlWriter.WriteStartElement('SkypeSettings')
      $xmlWriter.WriteStartElement('Theming')
      $xmlWriter.WriteElementString('ThemeName', 'Custom')
      $xmlWriter.WriteElementString('CustomThemeImageUrl','wallpaper.jpg')
      $xmlWriter.WriteStartElement('CustomThemeColor')
      $xmlWriter.WriteElementString('RedComponent','100')
      $xmlWriter.WriteElementString('GreenComponent','100')
      $xmlWriter.WriteElementString('BlueComponent','100')
      $xmlWriter.WriteEndElement() # CustomThemeColor
      $xmlWriter.WriteEndElement() # Theming
      $xmlWriter.WriteEndElement() # SkypeSettings
      $xmlWriter.WriteEndDocument()
      $xmlWriter.Flush()
      $xmlWriter.Close()  
    }
  }
  
  New-MtrWallpaper