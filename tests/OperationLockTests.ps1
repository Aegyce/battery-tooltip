$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\tools\OperationLock.ps1')
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ('..\artifacts\operation-tests-' + [Guid]::NewGuid().ToString('N'))))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$helper = Join-Path $PSScriptRoot '..\tools\OperationLock.ps1'
$childScript = Join-Path $root 'child.ps1'
[IO.File]::WriteAllText($childScript,@'
param($Helper,$Root)
$ErrorActionPreference = 'Stop'
. $Helper
[IO.File]::WriteAllText((Join-Path $Root 'ready'),'ready')
$mutex = Enter-BatteryTooltipOperation $Root
try { [IO.File]::WriteAllText((Join-Path $Root 'entered'),'entered') }
finally { Exit-BatteryTooltipOperation $mutex }
'@)
$checks = 0
$first = Enter-BatteryTooltipOperation $root
$child = $null
try {
    $nested = Enter-BatteryTooltipOperation $root
    Exit-BatteryTooltipOperation $nested
    $checks++
    $other = Enter-BatteryTooltipOperation (Join-Path $root 'another installation')
    Exit-BatteryTooltipOperation $other
    $checks++
    $command = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Helper "{1}" -Root "{2}"' -f $childScript,$helper,$root
    $child = Start-Process -FilePath powershell.exe -ArgumentList $command -WindowStyle Hidden -PassThru
    $null = $child.Handle
    $deadline = (Get-Date).AddSeconds(10)
    while (-not (Test-Path -LiteralPath (Join-Path $root 'ready')) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 50 }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'ready'))) { throw 'Child did not begin.' }
    Start-Sleep -Milliseconds 200
    if (Test-Path -LiteralPath (Join-Path $root 'entered')) { throw 'Conflicting operation entered while another operation owned the mutex.' }
    $checks++
    Exit-BatteryTooltipOperation $first
    $first = $null
    if (-not $child.WaitForExit(10000) -or $child.ExitCode -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $root 'entered'))) { throw 'Waiting operation did not enter after release.' }
    $checks++
    Write-Host "$checks operation serialization checks passed."
} finally {
    if ($first) { Exit-BatteryTooltipOperation $first }
    if ($child) { if (-not $child.HasExited) { Stop-Process -Id $child.Id -Force }; $child.Dispose() }
}
