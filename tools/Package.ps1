$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WriteConfig.ps1')
$root = Split-Path -Parent $PSScriptRoot
$version = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
$config = Read-ModConfig (Join-Path $root 'runtime\windhawk\AppData\Engine\Mods\local@battery-tooltip.ini')
$library = [regex]::Match($config,'(?m)^LibraryFileName=([^\r\n]+)').Groups[1].Value.Trim()
if ($library -notmatch ('^battery-tooltip_' + [regex]::Escape($version) + '_\d+\.dll$')) { throw 'Build the current version before packaging.' }
$package = Join-Path $root ('artifacts\package-' + [Guid]::NewGuid().ToString('N'))
$precompiled = Join-Path $package 'Precompiled'
New-Item -ItemType Directory -Path $precompiled -Force | Out-Null
foreach ($name in @('battery-tooltip.wh.cpp','README.md','LICENSE','VERSION','Setup.cmd','Install.cmd','Start.cmd','Rollback.cmd','Status.cmd')) {
    Copy-Item -LiteralPath (Join-Path $root $name) -Destination $package
}
foreach ($name in @('tools','tests')) { Copy-Item -LiteralPath (Join-Path $root $name) -Destination $package -Recurse }
$entries = foreach ($name in @($library,'libc++.whl','libunwind.whl','windhawk-mod-shim.dll')) {
    $file = Join-Path $root "runtime\windhawk\AppData\Engine\Mods\64\$name"
    Copy-Item -LiteralPath $file -Destination $precompiled
    [ordered]@{name=$name;sha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()}
}
@{version=$version;files=@($entries)} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $precompiled 'manifest.json') -Encoding UTF8
$archive = Join-Path $root "artifacts\BatteryTooltip-$version.zip"
Compress-Archive -Path (Join-Path $package '*') -DestinationPath $archive -Force
Copy-Item -LiteralPath (Join-Path $root 'battery-tooltip.wh.cpp') -Destination (Join-Path $root 'artifacts\battery-tooltip.wh.cpp') -Force
$checksums = foreach ($file in @($archive,(Join-Path $root 'artifacts\battery-tooltip.wh.cpp'))) {
    "{0}  {1}" -f (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant(),(Split-Path $file -Leaf)
}
$checksums | Set-Content -LiteralPath (Join-Path $root 'artifacts\SHA256SUMS.txt') -Encoding ascii
Write-Host "Package created: $archive"
