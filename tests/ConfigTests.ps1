$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\tools\WriteConfig.ps1')
$testRoot = Join-Path $PSScriptRoot ('..\artifacts\config-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$path = [IO.Path]::GetFullPath((Join-Path $testRoot 'mod.ini'))
$old = "[Mod]`nLibraryFileName=old.dll`nDisabled=1`n[Settings]`nlanguage=auto`n"
$new = "[Mod]`nLibraryFileName=new.dll`nDisabled=0`n[Settings]`nlanguage=en`n"
$script:checks = 0
function Check([bool]$Condition,[string]$Name) {
    if (-not $Condition) { throw "FAILED: $Name" }
    $script:checks++
}

Write-ModConfig $path $old
Check ([IO.File]::ReadAllText($path) -eq $old) 'first creation'
Write-ModConfig $path $new
Check ([IO.File]::ReadAllText($path) -eq $new) 'replacement'
Check ([IO.File]::ReadAllText("$path.bak") -eq $old) 'valid backup'
foreach ($bad in @('',"[Mod]`nDisabled=0`n[Settings]`n", "[Mod]`nLibraryFileName=../bad.dll`nDisabled=0`n[Settings]`n")) {
    $failed = $false
    try { Write-ModConfig $path $bad } catch { $failed = $true }
    Check ($failed -and [IO.File]::ReadAllText($path) -eq $new) 'reject invalid data without touching original'
}

# A real Windows handle denying deletion makes atomic replacement fail.
# Even after all retries, the complete original and backup must survive.
$reader = [IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
$failed = $false
try {
    try { Write-ModConfig $path $old } catch { $failed = $true }
} finally { $reader.Dispose() }
Check ($failed -and [IO.File]::ReadAllText($path) -eq $new) 'reader lock preserves original on failure'
Check ([IO.File]::ReadAllText("$path.bak") -eq $old) 'reader lock preserves backup'
Check (@(Get-ChildItem -LiteralPath $testRoot -Filter '*.tmp*').Count -eq 0) 'temporary files removed on failure'
Write-ModConfig $path $old
Check ([IO.File]::ReadAllText($path) -eq $old) 'successful write after lock is released'

[IO.File]::WriteAllText($path,'') # Simulate the observed 0-byte configuration.
$recovered = Read-ModConfig $path
Check ($recovered -eq $new) 'read from backup after truncation'
Write-ModConfig $path $recovered
Check ([IO.File]::ReadAllText($path) -eq $new) 'restore damaged configuration'
Check ([IO.File]::ReadAllText("$path.bak") -eq $new) 'damaged original does not overwrite valid backup'
Write-Host "$script:checks configuration checks passed."
