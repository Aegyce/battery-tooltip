param([ValidateSet('Enable','Disable','Status')][string]$Mode,[ValidatePattern('^[a-f0-9]{32}$')][string]$Token)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$response = Join-Path $root "artifacts\startup-requests\$Token.json"
try {
    . (Join-Path $PSScriptRoot 'StartupConfig.ps1')
    $script:BatteryTooltipStartupDesktopContext = $true
    $enabled = Set-BatteryTooltipStartup $root $Mode
    $item = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name BatteryTooltip -ErrorAction SilentlyContinue
    $current = if ($item) { $item.BatteryTooltip } else { $null }
    $result = @{Success=$true;Enabled=$enabled;Current=$current;Error=$null}
} catch { $result = @{Success=$false;Enabled=$false;Current=$null;Error=$_.Exception.Message} }
$result | ConvertTo-Json | Set-Content -LiteralPath "$response.tmp" -Encoding UTF8
[IO.File]::Move("$response.tmp",$response)
