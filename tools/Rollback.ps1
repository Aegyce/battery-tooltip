param([switch]$KeepAutoStart, [switch]$KeepRecoveryMonitor)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WriteConfig.ps1')
. (Join-Path $PSScriptRoot 'StartupConfig.ps1')
. (Join-Path $PSScriptRoot 'WatchControl.ps1')
. (Join-Path $PSScriptRoot 'OperationLock.ps1')
$projectRoot = Split-Path -Parent $PSScriptRoot
$operation = Enter-BatteryTooltipOperation $projectRoot
try {
    if (-not $KeepAutoStart) { Set-BatteryTooltipStartup $projectRoot Disable | Out-Null }
    $exe = Join-Path $projectRoot 'runtime\windhawk\windhawk.exe'
    $iniPath = Join-Path $projectRoot 'runtime\windhawk\AppData\Engine\Mods\local@battery-tooltip.ini'
    if (Test-Path -LiteralPath $iniPath) {
        $text = Read-ModConfig $iniPath
        Write-ModConfig $iniPath ($text.Replace('Disabled=0','Disabled=1'))
        if (-not $KeepRecoveryMonitor) { Stop-BatteryTooltipWatch $projectRoot }
        $deadline = (Get-Date).AddSeconds(15)
        do {
            $loaded = @(Get-Process explorer -ErrorAction SilentlyContinue | ForEach-Object {
                $_.Modules | Where-Object { $_.FileName -like "$projectRoot\runtime\windhawk\AppData\Engine\Mods\64\battery-tooltip*" }
            })
            if ($loaded.Count -eq 0) { break }
            Start-Sleep -Milliseconds 300
        } while ((Get-Date) -lt $deadline)
        if ($loaded.Count -gt 0) { throw 'Battery tooltip DLL is still loaded. Rollback has not completed; do not delete files.' }
    } elseif (-not $KeepRecoveryMonitor) { Stop-BatteryTooltipWatch $projectRoot }
    if (Test-Path -LiteralPath $exe) {
        $process = Start-Process -FilePath $exe -ArgumentList '-exit -wait' -WindowStyle Hidden -PassThru
        $null = $process.Handle
        if (-not $process.WaitForExit(15000)) { throw 'Windhawk has not finished exiting. Do not delete the runtime yet.' }
        if ($process.ExitCode -ne 0) { throw "Windhawk exit failed: $($process.ExitCode)" }
    }
    if ($KeepAutoStart) { Write-Host 'Battery Tooltip stopped. Native battery tooltip restored. Automatic startup preference preserved.' }
    else { Write-Host 'Battery Tooltip stopped. Native battery tooltip restored and this copy removed from startup.' }
} finally { Exit-BatteryTooltipOperation $operation }
