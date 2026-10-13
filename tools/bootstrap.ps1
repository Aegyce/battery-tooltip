$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$runtimeRoot = Join-Path $projectRoot 'runtime\windhawk'
$installerPath = Join-Path $projectRoot 'artifacts\windhawk_setup_offline.exe'
New-Item -ItemType Directory -Path (Join-Path $projectRoot 'artifacts') -Force | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $runtimeRoot 'Compiler\bin\clang++.exe'))) {
    if (-not (Test-Path -LiteralPath $installerPath)) {
        Invoke-WebRequest -Uri 'https://github.com/ramensoftware/windhawk/releases/download/v1.7.3/windhawk_setup_offline.exe' -OutFile $installerPath -UseBasicParsing
    }
    $expectedHash = '4D93016570F982326EEBDFC9068E924FF21F6448534EA32672BB4C1D52A8193B'
    if ((Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash -ne $expectedHash) { throw 'Windhawk installer checksum mismatch.' }
    if ((Get-AuthenticodeSignature -LiteralPath $installerPath).Status -ne 'Valid') { throw 'Windhawk installer signature is not valid.' }
    $process = Start-Process -FilePath $installerPath -ArgumentList "/S /PORTABLE /D=$runtimeRoot" -WindowStyle Hidden -PassThru -Wait
    if ($process.ExitCode -ne 0) { throw "Portable extraction failed: $($process.ExitCode)" }
}
$settingsPath = Join-Path $runtimeRoot 'AppData\settings.ini'
$settings = [IO.File]::ReadAllText($settingsPath)
[IO.File]::WriteAllText($settingsPath,$settings.Replace('HideTrayIcon=0','HideTrayIcon=1'),[Text.UTF8Encoding]::new($false))
Write-Host 'Portable Windhawk prepared. No startup entry or hardware-reading driver was installed.'
