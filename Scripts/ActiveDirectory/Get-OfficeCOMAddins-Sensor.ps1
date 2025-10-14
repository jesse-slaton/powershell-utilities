$CTRPath = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"
[hashtable]$LoadBehaviorHash = @{
    0  = "Unloaded. Do not load automatically."
    1  = "Loaded. Do not load automatically."
    2  = "Unloaded. Load at startup."
    3  = "Loaded. Load at startup."
    8  = "Unloaded. Load on demand."
    9  = "Loaded. Load on demand."
    16 = "Loaded. Load first time, then load on demand."
}

Try {
    Test-Path -Path $CTRPath -ErrorAction Stop | Out-Null
}
Catch {
    Write-Error $_.Exception.Message -ErrorAction Stop
    [Environment]::Exit($_.Exception.HResult)
}

Switch ((Get-ItemProperty $CTRPath -ErrorAction SilentlyContinue).Platform) {
    'x64' { $HKLMPath = "HKLM:\SOFTWARE\Microsoft\Office" }
    'x86' { $HKLMPath = "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Office" }
}
$searchScopes = "HKCU:\SOFTWARE\Microsoft\Office", $HKLMPath
($searchScopes | ForEach-Object {
        Get-ChildItem -Path $_ -Recurse | `
                Where-Object -FilterScript { ($_.Name -like "*Addins*") -and ($_.ValueCount -gt 0) } | `
                    ForEach-Object { Get-ItemProperty -Path $_.PSPath } | `
                        Select-Object @{n = "Name"; e = { Split-Path $_.PSPath -leaf } } `
                        , @{n = "Product"; e = { (($_.PSPath -split '\\')[0, -3])[1] } } `
                        , FriendlyName `
                        , Loadbehavior `
                        , @{n = "Load Behavior Description"; e = { $LoadBehaviorHash.$($_.Loadbehavior) } } | `
                            Where-Object { $null -ne $_.Loadbehavior } | `
                                Sort-Object -Property Product, Name -Unique 
    } | `
            ConvertTo-Csv -Delimiter '|' -NoTypeInformation | `
            Select-Object -Skip 1
).Replace("`"","")