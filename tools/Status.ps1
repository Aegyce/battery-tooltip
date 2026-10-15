param([switch]$AsJson)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WriteConfig.ps1')
. (Join-Path $PSScriptRoot 'Runtime.ps1')
. (Join-Path $PSScriptRoot 'StartupConfig.ps1')
$projectRoot = Split-Path -Parent $PSScriptRoot
$text = Read-ModConfig (Join-Path $projectRoot 'runtime\windhawk\AppData\Engine\Mods\local@battery-tooltip.ini')
$library = [regex]::Match($text,'(?m)^LibraryFileName=([^\r\n]+)').Groups[1].Value.Trim()
$state = Get-BatteryTooltipRuntime $projectRoot $library
$state | Add-Member Version ([regex]::Match($text,'(?m)^Version=([^\r\n]+)').Groups[1].Value.Trim())
$state | Add-Member Enabled ($text -match '(?m)^Disabled=0\r?$')
$state | Add-Member StartupEnabled (Set-BatteryTooltipStartup $projectRoot Status)
if ($AsJson) { $state | ConvertTo-Json } else { $state | Format-List }
