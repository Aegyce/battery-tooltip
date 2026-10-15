param([ValidateRange(1,180)][int]$TimeoutSeconds = 30, [switch]$Quiet)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WriteConfig.ps1')
. (Join-Path $PSScriptRoot 'Runtime.ps1')
$projectRoot = Split-Path -Parent $PSScriptRoot
try {
    $exe = Join-Path $projectRoot 'runtime\windhawk\windhawk.exe'
    if (-not (Test-Path -LiteralPath $exe)) { throw 'Portable Windhawk runtime is missing.' }
    $iniPath = Join-Path $projectRoot 'runtime\windhawk\AppData\Engine\Mods\local@battery-tooltip.ini'
    $text = Read-ModConfig $iniPath
    $libraryName = [regex]::Match($text, '(?m)^LibraryFileName=(.+)').Groups[1].Value.Trim()
    if (-not $libraryName -or -not (Test-Path -LiteralPath (Join-Path $projectRoot "runtime\windhawk\AppData\Engine\Mods\64\$libraryName"))) { throw 'Build the battery tooltip mod first.' }
    Write-ModConfig $iniPath ([regex]::Replace($text,'(?m)^Disabled=[01]\r?$','Disabled=0'))
    Start-Process -FilePath $exe -ArgumentList '-tray-only' -WindowStyle Hidden
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $state = Get-BatteryTooltipRuntime $projectRoot $libraryName
        if ($state.HookReady) {
            if (-not $Quiet) { Write-Host 'Battery Tooltip is running. The native tooltip hook is ready.' }
            return
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    throw "Battery Tooltip did not become ready in $TimeoutSeconds seconds. $($state.LastError) Run Status.cmd for details."
} catch {
    $logDirectory = Join-Path $projectRoot 'artifacts'
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    Add-Content -LiteralPath (Join-Path $logDirectory 'startup.log') -Value "$(Get-Date -Format o) $($_.Exception.Message)"
    throw
}
