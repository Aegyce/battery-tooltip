$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\tools\ShellIdentity.ps1')
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$checks = 0
function Check([bool]$Condition,[string]$Name) {
    if (-not $Condition) { throw "FAILED: $Name" }
    $script:checks++
}
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\artifacts\shell identity & test'))
$window = [Windows.Window]::new()
$window.ShowInTaskbar = $false
try {
    $handle = [Windows.Interop.WindowInteropHelper]::new($window).EnsureHandle()
    [BatteryTooltip.ShellIdentity]::ConfigureWindow($handle,$root)
    Check ([BatteryTooltip.ShellIdentity]::GetWindowProperty($handle,5) -eq [BatteryTooltip.ShellIdentity]::AppId) 'window has its own application identity'
    Check ([BatteryTooltip.ShellIdentity]::GetWindowProperty($handle,2) -eq ('"{0}"' -f (Join-Path $root 'tools\BatteryTooltip.exe'))) 'taskbar relaunch opens the GUI launcher with a quoted path'
    Check ([BatteryTooltip.ShellIdentity]::GetWindowProperty($handle,3) -eq ((Join-Path $root 'assets\battery-tooltip.ico') + ',0')) 'taskbar uses the battery icon even without a shortcut'
    Check ([BatteryTooltip.ShellIdentity]::GetWindowProperty($handle,4) -eq 'Battery Tooltip') 'taskbar uses the application name'
    [BatteryTooltip.ShellIdentity]::ClearWindow($handle)
    foreach ($property in @(2,3,4,5)) {
        Check (-not [BatteryTooltip.ShellIdentity]::GetWindowProperty($handle,$property)) "window releases shell property $property on close"
    }
} finally { $window.Close() }
Write-Host "$checks shell identity checks passed."
