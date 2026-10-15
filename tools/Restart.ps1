$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Rollback.ps1') -KeepAutoStart
& (Join-Path $PSScriptRoot 'Start.ps1')
Write-Host 'Battery Tooltip restarted. Automatic startup preference was preserved.'
