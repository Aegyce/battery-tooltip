$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'OperationLock.ps1')
. (Join-Path $PSScriptRoot 'WriteConfig.ps1')
. (Join-Path $PSScriptRoot 'WatchControl.ps1')
. (Join-Path $PSScriptRoot 'NativeProcess.ps1')
$operation = Enter-BatteryTooltipOperation $root
try {
    $configPath = Join-Path $root 'runtime\windhawk\AppData\Engine\Mods\local@battery-tooltip.ini'
    if (-not (Get-BatteryTooltipWatchRunning $root) -or -not (Test-Path -LiteralPath $configPath)) { return }
    $text = Read-ModConfig $configPath
    if ($text -notmatch '(?m)^Disabled=0\r?$' -or $text -match '(?m)^autoRecover=0\r?$') { return }
    $original = $text
    # A replacement controller must be alive to process unload requests left
    # behind by a forcibly terminated portable controller.
    $exe = Join-Path $root 'runtime\windhawk\windhawk.exe'
    Start-BatteryTooltipDesktopProcess $exe '-tray-only' $root
    $deadline = (Get-Date).AddSeconds(5)
    do {
        $active = @(Get-CimInstance Win32_Process -Filter "Name = 'windhawk.exe'" | Where-Object { $_.ExecutablePath -eq $exe })
        if ($active.Count) { break }
        Start-Sleep -Milliseconds 100
    } while ((Get-Date) -lt $deadline)
    if (-not $active.Count) { throw 'The recovery controller did not start.' }
    # Reuse the normal, verified unload and atomic-config paths. The monitor
    # remains alive and knows this worker temporarily disables the module.
    & (Join-Path $PSScriptRoot 'Rollback.ps1') -KeepAutoStart -KeepRecoveryMonitor
    if (-not (Get-BatteryTooltipWatchRunning $root)) { return }
    $text = Read-ModConfig $configPath
    if ($text -match '(?m)^autoRecover=0\r?$') { return }
    & (Join-Path $PSScriptRoot 'Start.ps1') -TimeoutSeconds 10 -Quiet
} catch {
    if ($original -and (Get-BatteryTooltipWatchRunning $root) -and (Test-Path -LiteralPath $configPath)) {
        $current = Read-ModConfig $configPath
        $disabled = $original.Replace('Disabled=0','Disabled=1')
        if ($current -eq $disabled) { Write-ModConfig $configPath $original }
    }
    $directory = Join-Path $root 'artifacts'
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    Add-Content -LiteralPath (Join-Path $directory 'recovery-error.log') -Value "$(Get-Date -Format o) $($_.Exception.Message)"
    throw
} finally { Exit-BatteryTooltipOperation $operation }
