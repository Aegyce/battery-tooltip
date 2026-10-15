function Install-BatteryTooltipPackage([string]$ProjectRoot) {
    . (Join-Path $PSScriptRoot 'WriteConfig.ps1')
    $version = [IO.File]::ReadAllText((Join-Path $ProjectRoot 'VERSION')).Trim()
    $package = Join-Path $ProjectRoot 'Precompiled'
    $manifestPath = Join-Path $package 'manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.version -ne $version) { throw 'Precompiled package version does not match VERSION.' }
    $names = @($manifest.files | ForEach-Object { $_.name })
    $libraries = @($names | Where-Object { $_ -match ('^battery-tooltip_' + [regex]::Escape($version) + '_\d+\.dll$') })
    if ($libraries.Count -ne 1 -or $names.Count -ne 4 -or
        'libc++.whl' -notin $names -or 'libunwind.whl' -notin $names -or 'windhawk-mod-shim.dll' -notin $names) {
        throw 'Precompiled package must contain one mod and its three runtime dependencies.'
    }
    foreach ($entry in $manifest.files) {
        if ($entry.name -match '[/\\]' -or $entry.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid package manifest entry.' }
        $file = Join-Path $package $entry.name
        if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $entry.sha256) {
            throw "Package checksum mismatch: $($entry.name)"
        }
    }
    $mods = Join-Path $ProjectRoot 'runtime\windhawk\AppData\Engine\Mods'
    $destination = Join-Path $mods '64'
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    foreach ($entry in $manifest.files) { Copy-Item -LiteralPath (Join-Path $package $entry.name) -Destination $destination -Force }
    $iniPath = Join-Path $mods 'local@battery-tooltip.ini'
    $settings = "[Settings]`nlanguage=auto`npreviewMode=0`nchargeTargetPercent=100`n"
    if ((Test-Path -LiteralPath $iniPath) -or (Test-Path -LiteralPath "$iniPath.bak")) {
        $previous = Read-ModConfig $iniPath
        $settings = [regex]::Match($previous,'(?ms)^\[Settings\]\r?\n.*').Value
    }
    $config = "[Mod]`nLibraryFileName=$($libraries[0])`nDisabled=1`nLoggingEnabled=1`nDebugLoggingEnabled=0`nInclude=explorer.exe`nExclude=`nArchitecture=x86-64`nVersion=$version`n$settings"
    Write-ModConfig $iniPath $config
    $sources = Join-Path $ProjectRoot 'runtime\windhawk\AppData\ModsSource'
    New-Item -ItemType Directory -Path $sources -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'battery-tooltip.wh.cpp') -Destination (Join-Path $sources 'local@battery-tooltip.wh.cpp') -Force
}
