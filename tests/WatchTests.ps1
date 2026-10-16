$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\tools\WatchControl.ps1')
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ('..\artifacts\watch-tests-' + [Guid]::NewGuid().ToString('N'))))
$tools = Join-Path $root 'tools'
$mods = Join-Path $root 'runtime\windhawk\AppData\Engine\Mods'
New-Item -ItemType Directory -Path $tools,$mods -Force | Out-Null
$launcher = Join-Path $tools 'BatteryTooltip.exe'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\tools\BatteryTooltip.exe') -Destination $launcher
$config = Join-Path $mods 'local@battery-tooltip.ini'
$log = Join-Path $root 'artifacts\runtime-watch.log'
$checks = 0
function Check([bool]$Condition,[string]$Name) { if (-not $Condition) { throw "FAILED: $Name" }; $script:checks++ }
function Monitors {
    @(Get-CimInstance Win32_Process -Filter "Name = 'BatteryTooltip.exe'" | Where-Object { $_.ExecutablePath -eq $launcher -and $_.CommandLine -match '--desktop --watch' })
}
function Wait-For([scriptblock]$Condition,[string]$Name) {
    $deadline = (Get-Date).AddSeconds(12)
    do { if (& $Condition) { return }; Start-Sleep -Milliseconds 100 } while ((Get-Date) -lt $deadline)
    throw "Timed out: $Name"
}
try {
    # A malformed configuration must suspend recovery without launching anything.
    [IO.File]::WriteAllText($config,"[Mod]`nDisabled=invalid`n")
    Start-Process -FilePath $launcher -ArgumentList '--desktop --watch' -WindowStyle Hidden
    Wait-For { (Test-Path -LiteralPath $log) -and [IO.File]::ReadAllText($log).Contains('Configuration invalid') } 'invalid config observation'
    Check (@(Monitors).Count -eq 1) 'one monitor runs without a valid start authorization'
    Start-Process -FilePath $launcher -ArgumentList '--desktop --watch' -WindowStyle Hidden
    Start-Sleep -Milliseconds 500
    Check (@(Monitors).Count -eq 1) 'duplicate monitor launch remains a singleton'
    Check (-not [IO.File]::ReadAllText($log).Contains('Recovery Start')) 'invalid configuration never starts a runtime'
    [IO.File]::WriteAllText($config,"[Mod]`nDisabled=1`n")
    Stop-BatteryTooltipWatch $root
    Check (@(Monitors).Count -eq 0) 'stop waits until the monitor has exited'
    Start-Sleep -Milliseconds 500
    Check (@(Monitors).Count -eq 0) 'a stopped monitor does not resurrect itself'
    [IO.File]::WriteAllText($config,"[Mod]`nDisabled=0`n[Settings]`nautoRecover=0`n")
    Start-Process -FilePath $launcher -ArgumentList '--desktop --watch' -WindowStyle Hidden
    Wait-For { [IO.File]::ReadAllText($log).Contains('Monitor stopped by configuration') -and @(Monitors).Count -eq 0 } 'recovery opt-out'
    Check (-not [IO.File]::ReadAllText($log).Contains('Recovery Start')) 'recovery opt-out is honored'
    Check (@(Monitors).Count -eq 0) 'opt-out leaves no persistent monitor'
    Write-Host "$checks recovery monitor integration checks passed."
} finally { Stop-BatteryTooltipWatch $root }
