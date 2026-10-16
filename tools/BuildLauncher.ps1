$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$compiler = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compiler /nologo /target:winexe /platform:x64 /optimize+ /reference:System.Windows.Forms.dll /reference:Microsoft.CSharp.dll "/win32icon:$root\assets\battery-tooltip.ico" "/out:$PSScriptRoot\BatteryTooltip.exe" (Join-Path $PSScriptRoot 'Launcher.cs') (Join-Path $PSScriptRoot 'NativeProcess.cs') (Join-Path $PSScriptRoot 'RuntimeWatch.cs') (Join-Path $PSScriptRoot 'RecoveryPolicy.cs') (Join-Path $PSScriptRoot 'PowerNotificationWindow.cs')
if ($LASTEXITCODE -ne 0) { throw 'Battery Tooltip launcher build failed.' }
