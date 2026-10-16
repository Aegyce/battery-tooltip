$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Path (Join-Path $PSScriptRoot '..\tools\PowerNotificationWindow.cs') -ReferencedAssemblies System.dll,System.Windows.Forms.dll
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class NativePowerProbe {
 [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr window,uint message,IntPtr value,IntPtr data);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
 [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr window);
}
'@
$script:resumes = 0
$checks = 0
function Check([bool]$Condition,[string]$Name) { if (-not $Condition) { throw "FAILED: $Name" }; $script:checks++ }
$window = [BatteryTooltip.PowerNotificationWindow]::new([Action]{ $script:resumes++ })
$handle = $window.Handle
try {
    Check ([NativePowerProbe]::IsWindow($handle) -and -not [NativePowerProbe]::IsWindowVisible($handle)) 'monitor listens through an invisible native window'
    [NativePowerProbe]::SendMessage($handle,0x218,[IntPtr]18,[IntPtr]::Zero) | Out-Null
    Check ($script:resumes -eq 1) 'automatic resume is handled before any user activation'
    [NativePowerProbe]::SendMessage($handle,0x218,[IntPtr]7,[IntPtr]::Zero) | Out-Null
    Check ($script:resumes -eq 2) 'interactive resume is handled'
    [NativePowerProbe]::SendMessage($handle,0x218,[IntPtr]6,[IntPtr]::Zero) | Out-Null
    Check ($script:resumes -eq 3) 'critical resume is handled'
    [NativePowerProbe]::SendMessage($handle,0x218,[IntPtr]10,[IntPtr]::Zero) | Out-Null
    Check ($script:resumes -eq 3) 'a power-source change does not trigger resume recovery'
} finally { $window.Dispose() }
Check (-not [NativePowerProbe]::IsWindow($handle)) 'stopping the monitor destroys its notification window'
Write-Host "$checks power notification checks passed."
