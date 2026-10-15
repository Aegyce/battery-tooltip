if (-not ('BatteryTooltip.NativeTaskbar' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
namespace BatteryTooltip {
    public static class NativeTaskbar {
        [DllImport("kernel32.dll")]
        public static extern ushort GetUserDefaultUILanguage();
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern IntPtr FindWindow(string className, string windowName);
        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    }
}
'@
}

function Get-BatteryTooltipRuntime([string]$ProjectRoot, [string]$LibraryName) {
    $taskbar = [BatteryTooltip.NativeTaskbar]::FindWindow('Shell_TrayWnd',$null)
    $owner = [uint32]0
    [BatteryTooltip.NativeTaskbar]::GetWindowThreadProcessId($taskbar,[ref]$owner) | Out-Null
    $loaded = $false
    if ($owner) {
        $expected = Join-Path $ProjectRoot "runtime\windhawk\AppData\Engine\Mods\64\$LibraryName"
        $process = Get-Process -Id $owner -ErrorAction SilentlyContinue
        if ($process) {
            $loaded = @($process.Modules | Where-Object { $_.FileName -eq $expected }).Count -gt 0
        }
    }
    $storage = Join-Path $ProjectRoot 'runtime\windhawk\AppData\Engine\ModsWritable\local@battery-tooltip.ini'
    $text = ''
    try { $text = [IO.File]::ReadAllText($storage) } catch { }
    $runtimeOwner = [regex]::Match($text,'(?m)^runtimeProcessId=(\d+)').Groups[1].Value
    $state = [regex]::Match($text,'(?m)^runtimeStatus=([^\r\n]*)').Groups[1].Value.Trim()
    $errorText = [regex]::Match($text,'(?m)^lastError=([^\r\n]*)').Groups[1].Value.Trim()
    [pscustomobject]@{ExplorerProcessId=$owner;ModuleLoaded=$loaded;
        HookReady=($loaded -and $state -eq 'ready' -and $runtimeOwner -eq [string]$owner);
        RuntimeStatus=$state;LastError=$errorText}
}
