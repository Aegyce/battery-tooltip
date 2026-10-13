param([ValidateSet('auto','en','zh-CN')][string]$Language = 'auto')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WriteConfig.ps1')
$projectRoot = Split-Path -Parent $PSScriptRoot
$path = Join-Path $projectRoot 'runtime\windhawk\AppData\Engine\Mods\local@battery-tooltip.ini'
$text = Read-ModConfig $path
if ($text -match '(?m)^language=') {
    $text = [regex]::Replace($text,'(?m)^language=.+',"language=$Language")
} else { $text = $text.Replace('[Settings]',"[Settings]`nlanguage=$Language") }
$stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$previous = [regex]::Match($text,'(?m)^SettingsChangeTime=(\d+)').Groups[1].Value
if ($previous) { $stamp = [Math]::Max($stamp, [long]$previous + 1) }
if ($text -match '(?m)^SettingsChangeTime=') {
    $text = [regex]::Replace($text,'(?m)^SettingsChangeTime=\d+',"SettingsChangeTime=$stamp")
} else { $text = $text.Replace('[Mod]',"[Mod]`nSettingsChangeTime=$stamp") }
Write-ModConfig $path $text
Write-Host "Language selected: $Language. Reopen the battery tooltip to refresh."
