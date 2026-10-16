if (-not ('BatteryTooltip.ShellIdentity' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'ShellIdentity.cs')
}
