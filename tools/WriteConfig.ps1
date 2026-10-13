function Write-ModConfig([string]$Path, [string]$Text) {
    # Windhawk briefly locks its INI while reading a change. Retry only sharing
    # and lock violations; other errors must still be reported to the caller.
    for ($attempt = 0; $attempt -lt 8; $attempt++) {
        try {
            [IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))
            return
        } catch {
            $errorObject = $_.Exception
            if ($errorObject.InnerException) { $errorObject = $errorObject.InnerException }
            $code = $errorObject.HResult -band 0xffff
            if ($code -notin 32,33 -or $attempt -eq 7) { throw }
            Start-Sleep -Milliseconds ([Math]::Min(800,50 * [Math]::Pow(2,$attempt)))
        }
    }
}
