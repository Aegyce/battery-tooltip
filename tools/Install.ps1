param([switch]$NoAutoStart, [switch]$NoStart)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
# Stop the previous copy before replacing its DLL or runtime dependencies.
$exe = Join-Path $projectRoot 'runtime\windhawk\windhawk.exe'
if (Test-Path -LiteralPath $exe) { & (Join-Path $PSScriptRoot 'Rollback.ps1') }
& (Join-Path $PSScriptRoot 'bootstrap.ps1')
if (Test-Path -LiteralPath (Join-Path $projectRoot 'Precompiled\manifest.json')) {
    . (Join-Path $PSScriptRoot 'InstallPackage.ps1')
    Install-BatteryTooltipPackage $projectRoot
} else {
    & python (Join-Path $PSScriptRoot 'test.py')
    if ($LASTEXITCODE -ne 0) { throw 'Formatting tests failed. Python 3 is required when installing from source.' }
    & python (Join-Path $PSScriptRoot 'build.py')
    if ($LASTEXITCODE -ne 0) { throw 'Mod build failed.' }
}
if (-not $NoStart) { & (Join-Path $PSScriptRoot 'Start.ps1') }
if (-not $NoAutoStart) { & (Join-Path $PSScriptRoot 'Startup.ps1') -Mode Enable }
Write-Host 'Battery Tooltip installation complete. Use Status.cmd to inspect it or Rollback.cmd to stop it and remove startup.'
