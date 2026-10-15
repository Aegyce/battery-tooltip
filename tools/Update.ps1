param([ValidateSet('Check','Apply')][string]$Mode = 'Check', [string]$ProjectRoot = '',
    [string]$JobRoot = '', [int]$CheckingProcessId = 0)
$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
. (Join-Path $PSScriptRoot 'UpdateCore.ps1')
. (Join-Path $PSScriptRoot 'WriteConfig.ps1')
. (Join-Path $PSScriptRoot 'StartupConfig.ps1')
. (Join-Path $PSScriptRoot 'Menu.ps1')
. (Join-Path $PSScriptRoot 'Runtime.ps1')
Add-Type -AssemblyName PresentationFramework
$allStrings = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Manager.strings.json')) | ConvertFrom-Json
$text = Read-ModConfig (Join-Path $ProjectRoot 'runtime\windhawk\AppData\Engine\Mods\local@battery-tooltip.ini')
$language = [regex]::Match($text,'(?m)^language=([^\r\n]+)').Groups[1].Value.Trim()
$chinese = $language -eq 'zh-CN' -or ($language -eq 'auto' -and ([BatteryTooltip.NativeTaskbar]::GetUserDefaultUILanguage() -band 0x3ff) -eq 0x04)
$strings = if ($chinese) { $allStrings.zh } else { $allStrings.en }
$digest = [Security.Cryptography.SHA256]::Create()
try { $id = [BitConverter]::ToString($digest.ComputeHash([Text.Encoding]::UTF8.GetBytes($ProjectRoot.ToLowerInvariant()))).Replace('-','') }
finally { $digest.Dispose() }
$mutex = [Threading.Mutex]::new($false,"Local\BatteryTooltip.Update.$id")
$locked = $false
$handedOff = $false
$errorOccurred = $false
try {
    try { $locked = $mutex.WaitOne([TimeSpan]::FromSeconds($(if($Mode -eq 'Apply'){30}else{0}))) }
    catch [Threading.AbandonedMutexException] { $locked = $true }
    if (-not $locked) { [Windows.MessageBox]::Show($strings.updateBusy,'Battery Tooltip') | Out-Null; return }
    if ($Mode -eq 'Check') {
        Clear-BatteryTooltipStaleUpdates $ProjectRoot
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/Aegyce/battery-tooltip/releases/latest' -TimeoutSec 20 -Headers @{'User-Agent'='BatteryTooltip';Accept='application/vnd.github+json'}
        $current = [regex]::Match($text,'(?m)^Version=([^\r\n]+)').Groups[1].Value.Trim()
        $plan = Get-BatteryTooltipUpdatePlan $release $current
        if (-not $plan.Available) { [Windows.MessageBox]::Show(($strings.updateLatest -f $current),'Battery Tooltip') | Out-Null; return }
        $answer = [Windows.MessageBox]::Show(($strings.updateConfirm -f $current,$plan.Version),'Battery Tooltip',[Windows.MessageBoxButton]::YesNo,[Windows.MessageBoxImage]::Question,[Windows.MessageBoxResult]::No)
        if ($answer -ne [Windows.MessageBoxResult]::Yes) { return }
        $download = {
            param($uri,$destination)
            Invoke-WebRequest -Uri $uri -OutFile $destination -UseBasicParsing -TimeoutSec 120 -Headers @{'User-Agent'='BatteryTooltip'}
        }
        $JobRoot = New-BatteryTooltipPreparedUpdate $ProjectRoot $plan $download
        $shell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $command = '-NoProfile -STA -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Mode Apply -ProjectRoot "{1}" -JobRoot "{2}" -CheckingProcessId {3}' -f (Join-Path $JobRoot 'worker\Update.ps1'),$ProjectRoot,$JobRoot,$PID
        $worker = Start-Process -FilePath $shell -ArgumentList $command -WindowStyle Hidden -PassThru
        $markerPath = Join-Path $JobRoot 'owner.json'
        $owner = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
        $owner.processId = $worker.Id; $owner.processStart = $worker.StartTime.ToUniversalTime().Ticks
        $owner | ConvertTo-Json | Set-Content -LiteralPath $markerPath -Encoding UTF8
        $handedOff = $true
    } else {
        Assert-BatteryTooltipUpdateJob $ProjectRoot $JobRoot | Out-Null
        if ($CheckingProcessId) {
            $checking = Get-Process -Id $CheckingProcessId -ErrorAction SilentlyContinue
            if ($checking -and -not $checking.WaitForExit(15000)) { throw 'Update preparation did not finish.' }
        }
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class BatteryTooltipUpdateWindow {
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
}
'@
        $managerPath = [regex]::Escape((Join-Path $ProjectRoot 'tools\Manage.ps1'))
        foreach ($manager in Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'") {
            if ($manager.CommandLine -notmatch ('(?i)(?:^|\s)-File\s+"?' + $managerPath + '"?(?:\s|$)')) { continue }
            $process = Get-Process -Id $manager.ProcessId -ErrorAction SilentlyContinue
            if ($process) {
                $process.Refresh()
                if ($process.MainWindowHandle -eq [IntPtr]::Zero) { throw 'Cannot close the management window for updating.' }
                [BatteryTooltipUpdateWindow]::PostMessage($process.MainWindowHandle,0x10,[IntPtr]::Zero,[IntPtr]::Zero) | Out-Null
                if (-not $process.WaitForExit(15000)) { throw 'Management window did not close for updating.' }
            }
        }
        Install-BatteryTooltipPreparedUpdate $ProjectRoot $JobRoot | Out-Null
        $JobRoot = ''
    }
} catch {
    Write-BatteryTooltipUpdateLog $ProjectRoot $_.Exception.ToString()
    $errorOccurred = $true
} finally {
    if ($JobRoot -and -not $handedOff) {
        try { Remove-BatteryTooltipUpdateJob $ProjectRoot $JobRoot }
        catch { Write-BatteryTooltipUpdateLog $ProjectRoot "Cleanup deferred: $($_.Exception.Message)" }
    }
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
    if ($Mode -eq 'Apply') {
        $shell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        Start-Process -FilePath $shell -ArgumentList ('-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $ProjectRoot 'tools\Manage.ps1')) -WindowStyle Hidden
    }
}
if ($errorOccurred) { [Windows.MessageBox]::Show($strings.updateError,'Battery Tooltip',[Windows.MessageBoxButton]::OK,[Windows.MessageBoxImage]::Error) | Out-Null }
