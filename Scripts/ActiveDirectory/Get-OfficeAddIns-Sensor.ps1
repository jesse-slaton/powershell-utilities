$ClicktoRunPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
$HKCUBasePath = "HKCU:\SOFTWARE\Microsoft\Office"
$HKLMBasePath = "HKLM:\SOFTWARE\Microsoft\Office"
$HKLM32BasePath = "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Office"

$LoadBehaviorHashTable = @{
    0  = "Do not load (Unloaded)";
    1  = "Do not load (Loaded)";
    2  = "Load at startup (Unloaded)";
    3  = "Load at startup (Loaded)";
    8  = "Load on demand (Unloaded)";
    9  = "Load on demand (Loaded)";
    16 = "Load on demand (Loaded)";
}

Try {
    Test-Path -Path $ClicktoRunPath -ErrorAction Stop | Out-Null
}
Catch {
    Write-Error $_.Exception.Message -ErrorAction Stop
    [Environment]::Exit($_.Exception.HResult)   
}

$searchScopes = @(
    "$HKCUBasePath\*\Addins"
    , "$HKLMBasePath\*\Addins"
    , "$HKLM32BasePath\*\Addins"
)

$ArrayofOfficeAddins = $searchScopes | `
        ForEach-Object { Get-ChildItem -Path $_ -ErrorAction SilentlyContinue -Recurse | `
                ForEach-Object { Get-ItemProperty -Path $_.PSPath } | `
                    Select-Object @{n = "Hive"; e = { if ($_.PSParentPath -match '_USER') {'User'} else {'Machine'} } }`
                    , @{n = "Product"; e = { ((Convert-Path $_.PSParentPath) -split '\\')[4] } } `
                    , @{n = "Architecture"; e = { if ($_.PSPath -match 'Wow6432Node') { '32-bit' } else { '64-bit' } } }`
                    , @{n = "Name"; e = { Split-Path $_.PSPath -Leaf } } `
                    , FriendlyName `
                    , @{n = "LoadBehavior"; e = { $LoadBehaviorHashTable.($_.LoadBehavior) } } `
            } | `
                    Sort-Object -Unique -Property name
Try {
    $CSV = ($ArrayofOfficeAddins | Where-Object { $null -ne $_.LoadBehavior } | ConvertTo-Csv -Delimiter "|" -NoTypeInformation).Replace("`"", "")
    $CSV[1..($CSV.Length)] | Sort-Object 
}
Catch {
    #Write-Error $_.Exception.Message -ErrorAction Stop
    #[Environment]::Exit($_.Exception.HResult)   
}