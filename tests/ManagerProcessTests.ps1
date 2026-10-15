$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\tools\ManagerProcess.ps1')
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ('..\artifacts\manager-process-tests-' + [Guid]::NewGuid().ToString('N'))))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$child = Join-Path $root 'child with spaces.ps1'
[IO.File]::WriteAllText($child,'param([int]$Result) Write-Output "completed $Result"; [Console]::Error.WriteLine("diagnostic $Result"); exit $Result')
$checks = 0
foreach ($expected in @(0,7)) {
    $process = Start-BatteryTooltipManagerProcess $child "-Result $expected" $root
    try {
        $deadline = (Get-Date).AddSeconds(10)
        while (-not $process.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 50 }
        if (-not $process.HasExited) { throw 'Test child did not exit.' }
        $process.WaitForExit()
        if ($process.ExitCode -ne $expected) { throw "Expected real exit code $expected; got '$($process.ExitCode)'." }
        $checks++
        if ([IO.File]::ReadAllText((Join-Path $root 'manager-output.log')).Trim() -ne "completed $expected") { throw 'Output log was lost.' }
        $checks++
        if ([IO.File]::ReadAllText((Join-Path $root 'manager-error.log')).Trim() -ne "diagnostic $expected") { throw 'Error log was lost.' }
        $checks++
    } finally { $process.Dispose() }
}
Write-Host "$checks manager process checks passed."
