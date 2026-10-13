param([ValidateSet(0,1,2)][int]$Mode = 0)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$path = Join-Path $projectRoot 'runtime\windhawk\AppData\Engine\Mods\local@battery-tooltip.ini'
$text = [IO.File]::ReadAllText($path)
$text = [regex]::Replace($text,'(?m)^previewMode=\d+',"previewMode=$Mode")
$stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
if ($text -match '(?m)^SettingsChangeTime=') {
    $text = [regex]::Replace($text,'(?m)^SettingsChangeTime=\d+',"SettingsChangeTime=$stamp")
} else { $text = $text.Replace('[Mod]',"[Mod]`nSettingsChangeTime=$stamp") }
[IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))
if ($Mode -eq 0) { Write-Host 'Live telemetry selected.' }
else { Write-Host 'Sample preview selected. Values are fictional; hover over the original battery icon.' }
