$ErrorActionPreference = 'Stop'
Add-Type -Path (Join-Path $PSScriptRoot '..\tools\RecoveryPolicy.cs')
$checks = 0
function Check($Actual,$Expected,[string]$Name) {
    if ([string]$Actual -ne [string]$Expected) { throw "FAILED: $Name (expected $Expected, got $Actual)" }
    $script:checks++
}
$now = [datetime]::UtcNow
$policy = New-Object BatteryTooltip.RecoveryPolicy
Check ($policy.Evaluate($now,$false,$true,$false,$false,$false)) Stop 'manual stop prevents recovery'
Check ($policy.Evaluate($now,$true,$false,$false,$false,$false)) Stop 'recovery can be disabled independently'
Check ($policy.Evaluate($now,$null,$true,$false,$false,$false)) None 'unknown configuration never authorizes starting'
Check ($policy.Evaluate($now,$true,$true,$true,$true,$false)) None 'healthy runtime is preserved'
Check ($policy.Evaluate($now,$true,$true,$false,$false,$true)) Start 'missing runtime recovers after resume'
Check ($policy.Evaluate($now.AddSeconds(2),$true,$true,$false,$false,$false)) None 'repeated failures are delayed'
Check ($policy.Evaluate($now.AddSeconds(11),$true,$true,$false,$false,$false)) Start 'second attempt is permitted after delay'
Check ($policy.Evaluate($now.AddSeconds(32),$true,$true,$false,$false,$false)) Start 'third attempt is permitted after delay'
Check ($policy.Evaluate($now.AddSeconds(70),$true,$true,$false,$false,$true)) None 'resume does not defeat the restart budget'
Check $policy.Throttled $true 'restart storms are throttled'
Check ($policy.Evaluate($now.AddMinutes(11),$true,$true,$false,$false,$false)) Start 'recovery resumes after cooldown'
$policy = New-Object BatteryTooltip.RecoveryPolicy
Check ($policy.Evaluate($now,$true,$true,$true,$false,$false)) None 'hook initialization receives a grace period'
Check ($policy.Evaluate($now.AddSeconds(89),$true,$true,$true,$false,$false)) None 'hook is not restarted during initialization'
Check ($policy.Evaluate($now.AddSeconds(90),$true,$true,$true,$false,$false)) Restart 'persistently missing hook restarts the private runtime'
Check ($policy.Evaluate($now.AddSeconds(91),$false,$true,$true,$false,$false)) Stop 'manual stop wins during recovery'
Check ($policy.Evaluate($now.AddSeconds(92),$true,$true,$true,$true,$false)) None 'successful recovery is preserved'
$policy = New-Object BatteryTooltip.RecoveryPolicy
Check ($policy.Evaluate($now,$true,$true,$false,$false,$false)) Start 'first recovery reserves an attempt'
$policy.WorkerFailed()
Check ($policy.Evaluate($now.AddSeconds(11),$true,$true,$true,$false,$false)) Restart 'failed worker retries without another full initialization grace period'
Check ($policy.Evaluate($now.AddSeconds(12),$false,$true,$false,$false,$false)) Stop 'manual stop still wins after worker failure'
Write-Host "$checks recovery policy checks passed."
