# PSScriptAnalyzer settings for this repository.
#
# Enables the compatibility rules so Windows PowerShell 5.1 problems show up without a
# Windows host. Every other default rule still runs. CI reports these findings in the
# "PSScriptAnalyzer compatibility (informational)" step of the "PSScriptAnalyzer
# (informational)" job; to run them locally:
#
#   Invoke-ScriptAnalyzer -Path ./Scripts -Recurse -Settings ./PSScriptAnalyzerSettings.psd1 `
#       -IncludeRule PSUseCompatibleSyntax, PSUseCompatibleCommands, PSUseCompatibleTypes
#
# Invoke-ScriptAnalyzer (and the VS Code extension) also loads this file on its own when
# no -Settings is given and -Path is the repository root or a file directly in it.
# PSUseCompatibleSyntax reports at Error severity, so such a run with -Severity Error treats
# 7-only syntax as an error. Runs on files under Scripts/ or Modules/ (the Smoke tests) and
# -Path ./Scripts (CI) do not pick it up.
#
# Profiles are the ones bundled with PSScriptAnalyzer 1.23.0 (compatibility_profiles/):
#   win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework
#       Windows PowerShell 5.1 on Windows 10 1809 (client)
#   win-8_x64_10.0.17763.0_7.0.0_x64_3.1.2_core
#       PowerShell 7.0 on Windows Server 2019
@{
    Rules = @{
        PSUseCompatibleSyntax   = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.0')
        }
        PSUseCompatibleCommands = @{
            Enable         = $true
            TargetProfiles = @(
                'win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework'
                'win-8_x64_10.0.17763.0_7.0.0_x64_3.1.2_core'
            )
        }
        PSUseCompatibleTypes    = @{
            Enable         = $true
            TargetProfiles = @(
                'win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework'
                'win-8_x64_10.0.17763.0_7.0.0_x64_3.1.2_core'
            )
        }
    }
}
