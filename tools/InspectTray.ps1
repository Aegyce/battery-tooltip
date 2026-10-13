Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Drawing,System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class CursorNative {
 public struct POINT { public int X; public int Y; }
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
 [DllImport("user32.dll")] public static extern bool SetPhysicalCursorPos(int x, int y);
 [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
 [DllImport("user32.dll")] public static extern bool GetPhysicalCursorPos(out POINT point);
 [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
}
'@
[CursorNative]::SetProcessDpiAwarenessContext([IntPtr]::new(-4)) | Out-Null
$root = [System.Windows.Automation.AutomationElement]::RootElement
$tray = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ClassNameProperty, 'Shell_TrayWnd'))
if (-not $tray) { throw 'Taskbar not found' }
$all = $tray.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
foreach ($element in $all) {
    $info = $element.Current
    if ($info.Name -match '\u7535\u6c60|Battery|\u7535\u6e90' -or $info.AutomationId -match 'Power|Battery' -or $env:BATTERY_TOOLTIP_DUMP -eq '1') {
        [pscustomobject]@{Name=$info.Name;Id=$info.AutomationId;Class=$info.ClassName;Rect=$info.BoundingRectangle.ToString()} | Format-List
        if ($env:BATTERY_TOOLTIP_CAPTURE -eq '1' -and $info.BoundingRectangle.Width -gt 0) {
            $r = $info.BoundingRectangle
            $targetX = [int]($r.X + [Math]::Min(24,$r.Width/2))
            $targetY = [int]($r.Y + $r.Height/2)
            [CursorNative]::SetPhysicalCursorPos(100,100) | Out-Null
            Start-Sleep -Milliseconds 300
            $moved = [CursorNative]::SetPhysicalCursorPos($targetX,$targetY)
            [CursorNative]::mouse_event(1,0,0,0,[UIntPtr]::Zero)
            Start-Sleep -Milliseconds 1800
            $point = [CursorNative+POINT]::new()
            [CursorNative]::GetPhysicalCursorPos([ref]$point) | Out-Null
            Write-Host "Cursor moved=$moved actual=$($point.X),$($point.Y) target=$targetX,$targetY"
            $windows = $root.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.Condition]::TrueCondition)
            foreach ($window in $windows) {
                if ($window.Current.ClassName -match 'Popup|ToolTip') {
                    [pscustomobject]@{PopupName=$window.Current.Name;Class=$window.Current.ClassName;Rect=$window.Current.BoundingRectangle.ToString()} | Format-List
                }
            }
            $screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
            $left = [Math]::Max(0, [int]$r.X - 330)
            $top = [Math]::Max(0, [int]$r.Y - 220)
            $width = [Math]::Min(660, $screen.Width - $left)
            $height = [Math]::Min(320, $screen.Height - $top)
            $bitmap = [System.Drawing.Bitmap]::new($width,$height)
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            $graphics.CopyFromScreen([System.Drawing.Point]::new($left,$top),[System.Drawing.Point]::Empty,[System.Drawing.Size]::new($width,$height))
            $bitmap.Save((Join-Path $PSScriptRoot '..\artifacts\screen.png'))
            $graphics.Dispose(); $bitmap.Dispose()
        }
    }
}
