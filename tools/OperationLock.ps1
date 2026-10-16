function Enter-BatteryTooltipOperation([string]$ProjectRoot) {
    $hash = [Security.Cryptography.SHA256]::Create()
    try { $identity = [BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\').ToLowerInvariant()))).Replace('-','') }
    finally { $hash.Dispose() }
    $mutex = [Threading.Mutex]::new($false,"Local\BatteryTooltip.Operation.$identity")
    try {
        try { $owned = $mutex.WaitOne([TimeSpan]::FromSeconds(120)) }
        catch [Threading.AbandonedMutexException] { $owned = $true }
        if (-not $owned) { throw 'Another Battery Tooltip operation is still running. Wait for it to complete.' }
        return $mutex
    } catch { $mutex.Dispose(); throw }
}

function Exit-BatteryTooltipOperation($Mutex) {
    try { $Mutex.ReleaseMutex() } finally { $Mutex.Dispose() }
}
