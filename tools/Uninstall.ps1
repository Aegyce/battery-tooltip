$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'OperationLock.ps1')
$operation = Enter-BatteryTooltipOperation (Split-Path -Parent $PSScriptRoot)
try {
    & (Join-Path $PSScriptRoot 'Rollback.ps1')
    . (Join-Path $PSScriptRoot 'Menu.ps1')
    Set-BatteryTooltipMenu (Split-Path -Parent $PSScriptRoot) Disable | Out-Null
    Write-Host 'Battery Tooltip uninstalled. Startup and Start menu shortcuts were removed. The directory can now be deleted.'
} finally { Exit-BatteryTooltipOperation $operation }
