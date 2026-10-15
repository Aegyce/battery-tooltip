function Start-BatteryTooltipManagerProcess([string]$ScriptPath,[string]$Arguments,[string]$LogDirectory) {
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    $shell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $command = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" {1}' -f $ScriptPath,$Arguments
    $process = Start-Process -FilePath $shell -ArgumentList $command -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $LogDirectory 'manager-output.log') -RedirectStandardError (Join-Path $LogDirectory 'manager-error.log')
    # Windows PowerShell otherwise returns null ExitCode after a process exits.
    # Retain its handle while it is alive so completion preserves the real code.
    $null = $process.Handle
    return $process
}
