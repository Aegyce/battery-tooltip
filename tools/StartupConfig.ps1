function Get-BatteryTooltipStartupCommand([string]$ProjectRoot) {
    $shell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $script = Join-Path ([IO.Path]::GetFullPath($ProjectRoot)) 'tools\Start.ps1'
    return ('"{0}" -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{1}" -TimeoutSeconds 90 -Quiet' -f $shell,$script)
}

function Set-BatteryTooltipStartup {
    param([string]$ProjectRoot, [ValidateSet('Enable','Disable','Status')][string]$Mode,
        [string]$RegistryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run')
    $command = Get-BatteryTooltipStartupCommand $ProjectRoot
    $item = Get-ItemProperty -LiteralPath $RegistryPath -Name BatteryTooltip -ErrorAction SilentlyContinue
    $current = if ($item) { $item.BatteryTooltip } else { $null }
    if ($Mode -eq 'Enable') {
        if ($current -and $current -ne $command) {
            throw 'Another Battery Tooltip directory owns the startup entry. Disable startup from that directory before enabling this copy.'
        }
        if (-not (Test-Path -LiteralPath $RegistryPath)) { New-Item -Path $RegistryPath -Force | Out-Null }
        New-ItemProperty -LiteralPath $RegistryPath -Name BatteryTooltip -Value $command -PropertyType String -Force | Out-Null
    } elseif ($Mode -eq 'Disable' -and $current -eq $command) {
        Remove-ItemProperty -LiteralPath $RegistryPath -Name BatteryTooltip
    }
    $item = Get-ItemProperty -LiteralPath $RegistryPath -Name BatteryTooltip -ErrorAction SilentlyContinue
    return [bool]($item -and $item.BatteryTooltip -eq $command)
}
