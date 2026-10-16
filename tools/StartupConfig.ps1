function Get-BatteryTooltipStartupCommand([string]$ProjectRoot) {
    return ('"{0}" --start' -f (Join-Path ([IO.Path]::GetFullPath($ProjectRoot)) 'tools\BatteryTooltip.exe'))
}

function Set-BatteryTooltipStartup {
    param([string]$ProjectRoot, [ValidateSet('Enable','Disable','Status')][string]$Mode,
        [string]$RegistryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run')
    if ($RegistryPath -eq 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -and
        -not $script:BatteryTooltipStartupDesktopContext -and
        $env:BATTERY_TOOLTIP_DESKTOP_ROOT -ne [IO.Path]::GetFullPath($ProjectRoot)) {
        . (Join-Path $PSScriptRoot 'NativeProcess.ps1')
        $token = [Guid]::NewGuid().ToString('N')
        $directory = Join-Path $ProjectRoot 'artifacts\startup-requests'
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $response = Join-Path $directory "$token.json"
        try {
            Start-BatteryTooltipDesktopProcess (Join-Path $ProjectRoot 'tools\BatteryTooltip.exe') "--startup-${Mode}:$token" $ProjectRoot
            $deadline = (Get-Date).AddSeconds(15)
            while (-not (Test-Path -LiteralPath $response) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 50 }
            if (-not (Test-Path -LiteralPath $response)) { throw 'Desktop startup registration did not respond. Check artifacts/launcher.log.' }
            $result = Get-Content -LiteralPath $response -Raw | ConvertFrom-Json
            if (-not $result.Success) { throw $result.Error }
            return [bool]$result.Enabled
        } finally {
            foreach ($path in @($response,"$response.tmp")) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force } }
        }
    }
    $command = Get-BatteryTooltipStartupCommand $ProjectRoot
    $item = Get-ItemProperty -LiteralPath $RegistryPath -Name BatteryTooltip -ErrorAction SilentlyContinue
    $current = if ($item) { $item.BatteryTooltip } else { $null }
    $owned = $current -eq $command
    if ($Mode -eq 'Enable') {
        if ($current -and -not $owned) {
            throw 'Another Battery Tooltip directory owns the startup entry. Disable startup from that directory before enabling this copy.'
        }
        if (-not (Test-Path -LiteralPath $RegistryPath)) { New-Item -Path $RegistryPath -Force | Out-Null }
        New-ItemProperty -LiteralPath $RegistryPath -Name BatteryTooltip -Value $command -PropertyType String -Force | Out-Null
    } elseif ($Mode -eq 'Disable' -and $owned) {
        Remove-ItemProperty -LiteralPath $RegistryPath -Name BatteryTooltip
    }
    $item = Get-ItemProperty -LiteralPath $RegistryPath -Name BatteryTooltip -ErrorAction SilentlyContinue
    return [bool]($item -and $item.BatteryTooltip -eq $command)
}
