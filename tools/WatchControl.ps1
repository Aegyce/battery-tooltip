function Get-BatteryTooltipWatchIdentity([string]$ProjectRoot) {
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\').ToLowerInvariant()))).Replace('-','') }
    finally { $hash.Dispose() }
}

function Stop-BatteryTooltipWatch([string]$ProjectRoot) {
    $identity = Get-BatteryTooltipWatchIdentity $ProjectRoot
    try { $signal = [Threading.EventWaitHandle]::OpenExisting("Local\BatteryTooltip.WatchStop.$identity") }
    catch [Threading.WaitHandleCannotBeOpenedException] { $signal = $null }
    if ($signal) { try { $signal.Set() | Out-Null } finally { $signal.Dispose() } }
    $expected = Join-Path $ProjectRoot 'tools\BatteryTooltip.exe'
    foreach ($item in Get-CimInstance Win32_Process -Filter "Name = 'BatteryTooltip.exe'") {
        if ($item.ExecutablePath -ne $expected -or $item.CommandLine -notmatch '(?:^|\s)--watch(?:\s|$)') { continue }
        $process = Get-Process -Id $item.ProcessId -ErrorAction SilentlyContinue
        if ($process) {
            try { if (-not $process.WaitForExit(15000)) { throw 'Battery Tooltip recovery monitor did not stop. Do not replace or delete the application files.' } }
            finally { $process.Dispose() }
        }
    }
}

function Get-BatteryTooltipWatchRunning([string]$ProjectRoot) {
    $identity = Get-BatteryTooltipWatchIdentity $ProjectRoot
    try {
        $signal = [Threading.EventWaitHandle]::OpenExisting("Local\BatteryTooltip.WatchStop.$identity")
        try { return -not $signal.WaitOne(0) } finally { $signal.Dispose() }
    } catch [Threading.WaitHandleCannotBeOpenedException] { return $false }
}
