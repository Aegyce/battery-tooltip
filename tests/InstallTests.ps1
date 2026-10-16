$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\tools\StartupConfig.ps1')
. (Join-Path $PSScriptRoot '..\tools\WriteConfig.ps1')
. (Join-Path $PSScriptRoot '..\tools\InstallPackage.ps1')
. (Join-Path $PSScriptRoot '..\tools\Menu.ps1')
$script:checks = 0
function Check([bool]$Condition,[string]$Name) {
    if (-not $Condition) { throw "FAILED: $Name" }
    $script:checks++
}
$token = [Guid]::NewGuid().ToString('N')
$registry = "HKCU:\Software\BatteryTooltip\Tests\$token"
$fixture = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\artifacts\install-tests-$token"))
$rootA = Join-Path $fixture 'path with spaces & symbols'
$rootB = Join-Path $fixture 'other copy'
try {
    Check (-not (Set-BatteryTooltipStartup $rootA Status $registry)) 'startup initially absent'
    Check (Set-BatteryTooltipStartup $rootA Enable $registry) 'enable startup'
    Check (Set-BatteryTooltipStartup $rootA Enable $registry) 'repeated enable is idempotent'
    $command = (Get-ItemProperty -LiteralPath $registry).BatteryTooltip
    Check ($command -eq ('"{0}" --start' -f (Join-Path $rootA 'tools\BatteryTooltip.exe'))) 'startup uses the quoted console-free launcher'
    $failed = $false
    try { Set-BatteryTooltipStartup $rootB Enable $registry | Out-Null } catch { $failed = $true }
    Check ($failed -and (Get-ItemProperty -LiteralPath $registry).BatteryTooltip -eq $command) 'another directory cannot overwrite startup'
    Check (-not (Set-BatteryTooltipStartup $rootB Disable $registry)) 'other directory has no owned startup'
    Check ((Get-ItemProperty -LiteralPath $registry).BatteryTooltip -eq $command) 'other directory cannot remove startup'
    Check (-not (Set-BatteryTooltipStartup $rootA Disable $registry)) 'disable removes startup'
    Check (-not (Set-BatteryTooltipStartup $rootA Disable $registry)) 'repeated disable is safe'

    $precompiled = Join-Path $rootA 'Precompiled'
    New-Item -ItemType Directory -Path $precompiled -Force | Out-Null
    '1.0.0' | Set-Content -LiteralPath (Join-Path $rootA 'VERSION') -Encoding ascii
    '// fixture' | Set-Content -LiteralPath (Join-Path $rootA 'battery-tooltip.wh.cpp') -Encoding ascii
    $names = @('battery-tooltip_1.0.0_123.dll','libc++.whl','libunwind.whl','windhawk-mod-shim.dll')
    $entries = foreach ($name in $names) {
        $file = Join-Path $precompiled $name
        [IO.File]::WriteAllText($file,"fixture $name")
        @{name=$name;sha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash}
    }
    $manifest = Join-Path $precompiled 'manifest.json'
    @{version='1.0.0';files=@($entries)} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifest -Encoding UTF8
    Install-BatteryTooltipPackage $rootA
    $configPath = Join-Path $rootA 'runtime\windhawk\AppData\Engine\Mods\local@battery-tooltip.ini'
    $text = Read-ModConfig $configPath
    Check ($text -match 'Version=1.0.0' -and $text -match 'Disabled=1') 'new install remains disabled until started'
    Check ($text -match 'language=auto' -and $text -match 'previewMode=0') 'fresh install uses live telemetry'
    foreach ($name in $names) {
        Check (Test-Path -LiteralPath (Join-Path $rootA "runtime\windhawk\AppData\Engine\Mods\64\$name")) "dependency installed: $name"
    }
    Write-ModConfig $configPath ($text.Replace('language=auto','language=en').Replace('chargeTargetPercent=100','chargeTargetPercent=80'))
    Install-BatteryTooltipPackage $rootA
    $upgraded = Read-ModConfig $configPath
    Check ($upgraded -match 'language=en' -and $upgraded -match 'chargeTargetPercent=80') 'upgrade preserves language and charge target'
    $fixtureTools = Join-Path $rootA 'tools'
    New-Item -ItemType Directory -Path $fixtureTools -Force | Out-Null
    foreach ($name in @('Start.ps1','Runtime.ps1','WriteConfig.ps1','NativeProcess.ps1','NativeProcess.cs','OperationLock.ps1')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot "..\tools\$name") -Destination $fixtureTools
    }
    $failed = $false
    try { & (Join-Path $fixtureTools 'Start.ps1') -TimeoutSeconds 1 -Quiet } catch { $failed = $true }
    Check ($failed) 'missing runtime is reported as a failed start'
    Check ((Get-Content -LiteralPath (Join-Path $rootA 'artifacts\startup.log') -Raw) -match 'runtime is missing') 'startup failure is recorded for diagnosis'
    [IO.File]::WriteAllText((Join-Path $precompiled $names[0]),'tampered')
    $failed = $false
    try { Install-BatteryTooltipPackage $rootA } catch { $failed = $true }
    Check ($failed -and [IO.File]::ReadAllText($configPath) -eq $upgraded) 'checksum failure leaves installed configuration intact'
    $entries[0].name = '..\escape.dll'
    @{version='1.0.0';files=@($entries)} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifest -Encoding UTF8
    $failed = $false
    try { Install-BatteryTooltipPackage $rootA } catch { $failed = $true }
    Check ($failed) 'reject manifest path traversal'
    $menu = Join-Path $fixture 'Start menu'
    Check (Set-BatteryTooltipMenu $rootA Enable $menu) 'install manager shortcut'
    Check (@(Get-ChildItem -LiteralPath $menu -Filter '*.lnk').Count -eq 1) 'one Start menu entry covers all controls'
    $link = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $menu 'Battery Tooltip.lnk'))
    Check ($link.TargetPath -eq (Join-Path $rootA 'tools\BatteryTooltip.exe') -and -not $link.Arguments) 'manager shortcut uses the GUI launcher'
    Check ([BatteryTooltip.ShellIdentity]::GetShortcutAppId((Join-Path $menu 'Battery Tooltip.lnk')) -eq [BatteryTooltip.ShellIdentity]::AppId) 'shortcut identifies the manager independently of PowerShell'
    Check (Set-BatteryTooltipMenu $rootA Status $menu) 'manager shortcut ownership detected'
    $failed = $false
    try { Set-BatteryTooltipMenu $rootB Enable $menu | Out-Null } catch { $failed = $true }
    Check ($failed) 'another directory cannot replace the manager entry'
    Set-BatteryTooltipMenu $rootB Disable $menu | Out-Null
    Check (Set-BatteryTooltipMenu $rootA Status $menu) 'another directory cannot delete the manager entry'
    $marker = Join-Path $menu 'unrelated.txt'
    [IO.File]::WriteAllText($marker,'preserve')
    Set-BatteryTooltipMenu $rootA Disable $menu | Out-Null
    Check (-not (Set-BatteryTooltipMenu $rootA Status $menu)) 'uninstall removes the owned manager shortcut'
    Check (Test-Path -LiteralPath $marker) 'uninstall preserves unrelated menu files'
    Write-Host "$script:checks installation checks passed."
} finally {
    if (Test-Path -LiteralPath $registry) { Remove-Item -LiteralPath $registry }
}
