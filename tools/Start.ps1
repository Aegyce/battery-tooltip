$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WriteConfig.ps1')
$projectRoot = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $projectRoot 'runtime\windhawk\windhawk.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw 'Portable Windhawk runtime is missing.' }
$iniPath = Join-Path $projectRoot 'runtime\windhawk\AppData\Engine\Mods\local@battery-tooltip.ini'
$text = [IO.File]::ReadAllText($iniPath)
$libraryName = [regex]::Match($text, '(?m)^LibraryFileName=(.+)').Groups[1].Value.Trim()
if (-not $libraryName -or -not (Test-Path -LiteralPath (Join-Path $projectRoot "runtime\windhawk\AppData\Engine\Mods\64\$libraryName"))) { throw 'Build the battery tooltip mod first.' }
Write-ModConfig $iniPath ($text.Replace('Disabled=1','Disabled=0'))
Start-Process -FilePath $exe -ArgumentList '-tray-only' -WindowStyle Hidden
Write-Host 'Battery tooltip trial started. Hover over the original battery icon.'
