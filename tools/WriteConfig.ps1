function Assert-ModConfig([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { throw 'Battery tooltip configuration is empty.' }
    $section = [regex]::Match($Text, '(?ms)^\[Mod\]\r?\n(.*?)(?=^\[|\z)').Groups[1].Value
    $library = [regex]::Match($section, '(?m)^LibraryFileName=([^\r\n]+)').Groups[1].Value.Trim()
    if (-not $library -or $library -match '[/\\]' -or -not $library.EndsWith('.dll') -or
        $section -notmatch '(?m)^Disabled=[01]\r?$' -or $Text -notmatch '(?m)^\[Settings\]\r?$') {
        throw 'Battery tooltip configuration is incomplete or invalid.'
    }
}

function Read-ModConfig([string]$Path) {
    foreach ($candidate in @($Path, "$Path.bak")) {
        if (-not [IO.File]::Exists($candidate)) { continue }
        try {
            $text = [IO.File]::ReadAllText($candidate)
            Assert-ModConfig $text
            if ($candidate -ne $Path) { Write-Warning 'Using the last valid configuration backup.' }
            return $text
        } catch { $lastError = $_ }
    }
    throw "No valid battery tooltip configuration or backup exists at $Path. Run Setup.cmd to rebuild it. $lastError"
}

function Write-AtomicTextFile([string]$Path, [string]$Text, [string]$BackupPath = '') {
    if ([string]::IsNullOrWhiteSpace($Text)) { throw 'Refusing to write an empty configuration.' }
    $fullPath = [IO.Path]::GetFullPath($Path)
    $temporary = "$fullPath.$([Guid]::NewGuid().ToString('N')).tmp"
    $temporaryBackup = "$temporary.previous"
    try {
        # Complete the staged file before touching the destination. Replace
        # fails safely if a reader denies deletion; it never truncates the INI.
        [IO.File]::WriteAllText($temporary,$Text,[Text.UTF8Encoding]::new($false))
        for ($attempt = 0; $attempt -lt 8; $attempt++) {
            try {
                if ([IO.File]::Exists($fullPath)) {
                    $backup = if ($BackupPath) { [IO.Path]::GetFullPath($BackupPath) } else { $temporaryBackup }
                    [IO.File]::Replace($temporary,$fullPath,$backup)
                } else { [IO.File]::Move($temporary,$fullPath) }
                return
            } catch {
                $errorObject = $_.Exception
                if ($errorObject.InnerException) { $errorObject = $errorObject.InnerException }
                $code = $errorObject.HResult -band 0xffff
                if ($code -notin 32,33 -or $attempt -eq 7) { throw }
                Start-Sleep -Milliseconds ([Math]::Min(800,50 * [Math]::Pow(2,$attempt)))
            }
        }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
        if ([IO.File]::Exists($temporaryBackup)) { [IO.File]::Delete($temporaryBackup) }
    }
}

function Write-ModConfig([string]$Path, [string]$Text) {
    Assert-ModConfig $Text
    $backup = ''
    if ([IO.File]::Exists($Path)) {
        try {
            Assert-ModConfig ([IO.File]::ReadAllText($Path))
            $backup = "$Path.bak"
        } catch { } # Do not overwrite a valid backup with a corrupt original.
    }
    Write-AtomicTextFile $Path $Text $backup
}
