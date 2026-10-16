$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'OperationLock.ps1')
$operation = Enter-BatteryTooltipOperation (Split-Path -Parent $PSScriptRoot)
try {
    & (Join-Path $PSScriptRoot 'Rollback.ps1') -KeepAutoStart
    & (Join-Path $PSScriptRoot 'Start.ps1')
    Write-Host 'Battery Tooltip restarted. Automatic startup preference was preserved.'
} finally { Exit-BatteryTooltipOperation $operation }
