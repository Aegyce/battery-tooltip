param([ValidateSet('Enable','Disable','Status')][string]$Mode = 'Status')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'StartupConfig.ps1')
$enabled = Set-BatteryTooltipStartup (Split-Path -Parent $PSScriptRoot) $Mode
Write-Host "Battery Tooltip startup for this Windows user: $enabled"
