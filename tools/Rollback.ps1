$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WriteConfig.ps1')
$projectRoot = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $projectRoot 'runtime\windhawk\windhawk.exe'
$iniPath = Join-Path $projectRoot 'runtime\windhawk\AppData\Engine\Mods\local@battery-tooltip.ini'
if (Test-Path -LiteralPath $iniPath) {
    $text = [IO.File]::ReadAllText($iniPath)
    Write-ModConfig $iniPath ($text.Replace('Disabled=0','Disabled=1'))
    $deadline = (Get-Date).AddSeconds(15)
    do {
        $loaded = @(Get-Process explorer -ErrorAction SilentlyContinue | ForEach-Object {
            $_.Modules | Where-Object { $_.FileName -like "$projectRoot\runtime\windhawk\AppData\Engine\Mods\64\battery-tooltip*" }
        })
        if ($loaded.Count -eq 0) { break }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)
    if ($loaded.Count -gt 0) { throw 'Battery tooltip DLL is still loaded. Rollback has not completed; do not delete files.' }
}
if (Test-Path -LiteralPath $exe) {
    $process = Start-Process -FilePath $exe -ArgumentList '-exit -wait' -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(15000)) { throw 'Windhawk has not finished exiting. Do not delete the runtime yet.' }
    if ($process.ExitCode -ne 0) { throw "Windhawk exit failed: $($process.ExitCode)" }
}
Write-Host 'Trial stopped. Native battery tooltip restored. No startup entry was created.'
