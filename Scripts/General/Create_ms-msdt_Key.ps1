# Reg2CI (c) 2021 by Roger Zander
if ((Test-Path -LiteralPath "HKLM:\SOFTWARE\Classes\ms-msdt") -ne $true) { New-Item "HKLM:\SOFTWARE\Classes\ms-msdt" -Force -ea SilentlyContinue };
if ((Test-Path -LiteralPath "HKLM:\SOFTWARE\Classes\ms-msdt\shell") -ne $true) { New-Item "HKLM:\SOFTWARE\Classes\ms-msdt\shell" -Force -ea SilentlyContinue };
if ((Test-Path -LiteralPath "HKLM:\SOFTWARE\Classes\ms-msdt\shell\open") -ne $true) { New-Item "HKLM:\SOFTWARE\Classes\ms-msdt\shell\open" -Force -ea SilentlyContinue };
if ((Test-Path -LiteralPath "HKLM:\SOFTWARE\Classes\ms-msdt\shell\open\command") -ne $true) { New-Item "HKLM:\SOFTWARE\Classes\ms-msdt\shell\open\command" -Force -ea SilentlyContinue };
New-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Classes\ms-msdt' -Name '(default)' -Value 'URL:ms-msdt' -PropertyType String -Force -ea SilentlyContinue;
New-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Classes\ms-msdt' -Name 'EditFlags' -Value 2097152 -PropertyType DWord -Force -ea SilentlyContinue;
New-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Classes\ms-msdt' -Name 'URL Protocol' -Value '' -PropertyType String -Force -ea SilentlyContinue;
New-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Classes\ms-msdt\shell\open\command' -Name '(default)' -Value '"%SystemRoot%\system32\msdt.exe" %1' -PropertyType ExpandString -Force -ea SilentlyContinue;
