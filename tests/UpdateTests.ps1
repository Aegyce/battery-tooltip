$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\tools\UpdateCore.ps1')
. (Join-Path $PSScriptRoot '..\tools\WriteConfig.ps1')
. (Join-Path $PSScriptRoot '..\tools\InstallPackage.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$script:checks = 0
function Check([bool]$Condition,[string]$Name) {
    if (-not $Condition) { throw "FAILED: $Name" }
    $script:checks++
}
function Reject([scriptblock]$Action,[string]$Name) {
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    Check $failed $Name
}
$testRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ('..\artifacts\update-tests-' + [Guid]::NewGuid().ToString('N'))))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$release = [pscustomobject]@{tag_name='v1.2.0';draft=$false;prerelease=$false;assets=@(
    [pscustomobject]@{name='BatteryTooltip-1.2.0.zip';browser_download_url='https://github.com/Aegyce/battery-tooltip/releases/download/v1.2.0/BatteryTooltip-1.2.0.zip'},
    [pscustomobject]@{name='SHA256SUMS.txt';browser_download_url='https://github.com/Aegyce/battery-tooltip/releases/download/v1.2.0/SHA256SUMS.txt'})}
$plan = Get-BatteryTooltipUpdatePlan $release '1.1.0'
Check $plan.Available 'newer stable release is available'
Check (-not (Get-BatteryTooltipUpdatePlan $release '1.2.0').Available) 'same version does not update'
Check (-not (Get-BatteryTooltipUpdatePlan $release '1.10.0').Available) 'numeric comparison prevents downgrade'
Check ((Get-BatteryTooltipVersion 'v1.10.0') -gt (Get-BatteryTooltipVersion '1.2.0')) 'minor versions compare numerically'
Reject { Get-BatteryTooltipVersion 'v1.2.0-preview' } 'prerelease version rejected'
$release.prerelease=$true
Reject { Get-BatteryTooltipUpdatePlan $release '1.1.0' } 'prerelease metadata rejected'
$release.prerelease=$false
$release.assets[0].browser_download_url='https://example.com/BatteryTooltip-1.2.0.zip'
Reject { Get-BatteryTooltipUpdatePlan $release '1.1.0' } 'foreign download host rejected'
$release.assets[0].browser_download_url='https://github.com/Other/project/releases/download/v1.2.0/BatteryTooltip-1.2.0.zip'
Reject { Get-BatteryTooltipUpdatePlan $release '1.1.0' } 'foreign repository download rejected'
$release.assets[0].browser_download_url=$plan.PackageUrl

$payload = Join-Path $testRoot 'payload'
$precompiled = Join-Path $payload 'Precompiled'
$tools = Join-Path $payload 'tools'
New-Item -ItemType Directory -Path $precompiled,$tools -Force | Out-Null
'1.2.0' | Set-Content (Join-Path $payload 'VERSION') -Encoding ascii
'new source' | Set-Content (Join-Path $payload 'battery-tooltip.wh.cpp') -Encoding ascii
'new launcher fixture' | Set-Content (Join-Path $tools 'BatteryTooltip.exe') -Encoding ascii
foreach ($name in @('Start.ps1','Rollback.ps1','InstallPackage.ps1','Manage.ps1','NewFeature.ps1')) {
    "# new $name" | Set-Content (Join-Path $tools $name) -Encoding ascii
}
$entries = foreach ($name in @('battery-tooltip_1.2.0_123.dll','libc++.whl','libunwind.whl','windhawk-mod-shim.dll')) {
    $file = Join-Path $precompiled $name
    [IO.File]::WriteAllText($file,"fixture $name")
    @{name=$name;sha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash}
}
@{version='1.2.0';files=@($entries)} | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $precompiled 'manifest.json') -Encoding UTF8
$script:archive = Join-Path $testRoot 'BatteryTooltip-1.2.0.zip'
Compress-Archive -Path (Join-Path $payload '*') -DestinationPath $script:archive
$script:checksums = Join-Path $testRoot 'SHA256SUMS.txt'
"$((Get-FileHash $script:archive -Algorithm SHA256).Hash)  BatteryTooltip-1.2.0.zip" | Set-Content $script:checksums -Encoding ascii
$script:tamper = $false
$download = {
    param($uri,$destination)
    $source = if ($uri.EndsWith('SHA256SUMS.txt')) { $script:checksums } else { $script:archive }
    Copy-Item -LiteralPath $source -Destination $destination
    if ($script:tamper -and $uri.EndsWith('.zip')) { [IO.File]::AppendAllText($destination,'tampered') }
}
function New-Fixture([string]$Name) {
    $root = Join-Path $testRoot $Name
    New-Item -ItemType Directory -Path (Join-Path $root 'tools'),(Join-Path $root 'runtime\windhawk\AppData\Engine\Mods\64') -Force | Out-Null
    '1.1.0' | Set-Content (Join-Path $root 'VERSION') -Encoding ascii
    'old source' | Set-Content (Join-Path $root 'battery-tooltip.wh.cpp') -Encoding ascii
    'old launcher fixture' | Set-Content (Join-Path $root 'tools\BatteryTooltip.exe') -Encoding ascii
    '# old' | Set-Content (Join-Path $root 'tools\Manage.ps1') -Encoding ascii
    'keep this user file' | Set-Content (Join-Path $root 'user.txt') -Encoding ascii
    $config = "[Mod]`nLibraryFileName=battery-tooltip_1.1.0_1.dll`nDisabled=0`nVersion=1.1.0`n[Settings]`nlanguage=zh-CN`npreviewMode=0`nchargeTargetPercent=80`n"
    Write-ModConfig (Join-Path $root 'runtime\windhawk\AppData\Engine\Mods\local@battery-tooltip.ini') $config
    'old dll' | Set-Content (Join-Path $root 'runtime\windhawk\AppData\Engine\Mods\64\battery-tooltip_1.1.0_1.dll') -Encoding ascii
    return $root
}
$script:starts=0;$script:failNewStart=$false;$script:startup=$false;$script:running=$true
$actions = @{
    State = { param($root)
        $text=Read-ModConfig (Join-Path $root 'runtime\windhawk\AppData\Engine\Mods\local@battery-tooltip.ini')
        @{Version=[regex]::Match($text,'(?m)^Version=([^\r\n]+)').Groups[1].Value.Trim();Running=$script:running;Startup=$script:startup;Menu=$true}
    }
    Stop = {param($root) $script:running=$false}
    Install = {param($root) Install-BatteryTooltipPackage $root}
    Start = {param($root)
        $text=Read-ModConfig (Join-Path $root 'runtime\windhawk\AppData\Engine\Mods\local@battery-tooltip.ini')
        if ($script:failNewStart -and $text -match 'Version=1.2.0') { throw 'Injected new-version initialization failure' }
        $script:starts++;$script:running=$true
    }
    Preferences = {param($root,$state) $script:startup=$state.Startup}
}
$root=New-Fixture 'successful install with spaces'
$job=New-BatteryTooltipPreparedUpdate $root $plan $download
Check (Test-Path -LiteralPath (Join-Path $job $plan.PackageName)) 'download exists only inside owned staging directory'
$installed=Install-BatteryTooltipPreparedUpdate $root $job $actions
Check ($installed -eq '1.2.0') 'verified package installs'
Check ((Get-Content (Join-Path $root 'tools\BatteryTooltip.exe') -Raw).Trim() -eq 'new launcher fixture') 'update installs the GUI launcher'
$text=Read-ModConfig (Join-Path $root 'runtime\windhawk\AppData\Engine\Mods\local@battery-tooltip.ini')
Check ($text -match 'language=zh-CN' -and $text -match 'chargeTargetPercent=80') 'update preserves user settings'
Check (-not $script:startup -and $script:running) 'update preserves disabled startup and running state'
Check (-not (Test-Path -LiteralPath $job)) 'successful update removes zip, extraction, worker, and backup'
Check ((Get-Content (Join-Path $root 'user.txt') -Raw).Trim() -eq 'keep this user file') 'update preserves unrelated files'

$root=New-Fixture 'failed install'
$oldConfig=Read-ModConfig (Join-Path $root 'runtime\windhawk\AppData\Engine\Mods\local@battery-tooltip.ini')
$script:failNewStart=$true;$script:startup=$true;$script:running=$true
$job=New-BatteryTooltipPreparedUpdate $root $plan $download
Reject { Install-BatteryTooltipPreparedUpdate $root $job $actions } 'failed initialization is reported'
Check ((Get-Content (Join-Path $root 'VERSION') -Raw).Trim() -eq '1.1.0') 'failed update restores application version'
Check ((Get-Content (Join-Path $root 'tools\BatteryTooltip.exe') -Raw).Trim() -eq 'old launcher fixture') 'failed update restores the previous GUI launcher'
Check ((Read-ModConfig (Join-Path $root 'runtime\windhawk\AppData\Engine\Mods\local@battery-tooltip.ini')) -eq $oldConfig) 'failed update restores full mod configuration'
Check ($script:startup -and $script:running) 'rollback restores old running and startup state'
Check (-not (Test-Path (Join-Path $root 'tools\NewFeature.ps1'))) 'rollback removes files introduced by failed version'
Check (-not (Test-Path -LiteralPath $job)) 'failed update cleans all temporary installation files'
$script:failNewStart=$false

$root=New-Fixture 'stopped installation'
$script:running=$false;$beforeStarts=$script:starts
$job=New-BatteryTooltipPreparedUpdate $root $plan $download
Install-BatteryTooltipPreparedUpdate $root $job $actions | Out-Null
Check ($script:starts -eq $beforeStarts -and -not $script:running) 'update keeps a stopped installation stopped'

$root=New-Fixture 'tampered download'
$script:tamper=$true
Reject { New-BatteryTooltipPreparedUpdate $root $plan $download } 'archive checksum mismatch rejected before installation'
Check (@(Get-ChildItem (Join-Path $root 'artifacts\update-cache') -Directory).Count -eq 0) 'bad download is automatically removed'
Check ((Get-Content (Join-Path $root 'VERSION') -Raw).Trim() -eq '1.1.0') 'bad download leaves installation intact'
$script:tamper=$false

$evil=Join-Path $testRoot 'escape.zip'
$zip=[IO.Compression.ZipFile]::Open($evil,[IO.Compression.ZipArchiveMode]::Create)
try {$entry=$zip.CreateEntry('../outside.txt');$writer=[IO.StreamWriter]::new($entry.Open());$writer.Write('escape');$writer.Dispose()}finally{$zip.Dispose()}
Reject {Expand-BatteryTooltipUpdate $evil (Join-Path $testRoot 'escaped') '1.2.0'} 'archive traversal rejected before extraction'
Check (-not (Test-Path (Join-Path $testRoot 'outside.txt'))) 'archive cannot write outside staging'
$outside=Join-Path $testRoot 'do-not-delete'
New-Item -ItemType Directory -Path $outside | Out-Null
Reject {Remove-BatteryTooltipUpdateJob $root $outside} 'cleanup refuses directories outside its cache'
Check (Test-Path -LiteralPath $outside) 'unowned directory survives cleanup attempt'

$job=New-BatteryTooltipUpdateJob $root
$owner=Get-Content (Join-Path $job 'owner.json') -Raw | ConvertFrom-Json
$owner.processStart=0;$owner | ConvertTo-Json | Set-Content (Join-Path $job 'owner.json') -Encoding UTF8
Clear-BatteryTooltipStaleUpdates $root
Check (-not (Test-Path -LiteralPath $job)) 'next check cleans an interrupted update with a reused or dead process'
$job=New-BatteryTooltipUpdateJob $root
Clear-BatteryTooltipStaleUpdates $root
Check (Test-Path -LiteralPath $job) 'cleanup preserves an active update'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\tools\UpdateCore.ps1') -Destination (Join-Path $job 'UpdateCore.ps1')
$cleanupScript=Join-Path $job 'cleanup.ps1'
[IO.File]::WriteAllText($cleanupScript,'param($Root,$Job) $ErrorActionPreference="Stop"; . (Join-Path $PSScriptRoot "UpdateCore.ps1"); Remove-BatteryTooltipUpdateJob $Root $Job')
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cleanupScript -Root $root -Job $job
Check ($LASTEXITCODE -eq 0 -and -not (Test-Path -LiteralPath $job)) 'staged helper can remove its own script and installer directory'
Write-Host "$script:checks update checks passed."
