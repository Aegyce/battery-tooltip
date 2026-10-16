. (Join-Path $PSScriptRoot 'ShellIdentity.ps1')

function Set-BatteryTooltipMenu {
    param([string]$ProjectRoot, [ValidateSet('Enable','Disable','Status')][string]$Mode,
        [string]$MenuRoot = '')
    if (-not $MenuRoot) { $MenuRoot = Join-Path ([Environment]::GetFolderPath('Programs')) 'Battery Tooltip' }
    $ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
    $shell = New-Object -ComObject WScript.Shell
    $launcher = Join-Path $ProjectRoot 'tools\BatteryTooltip.exe'
    $entries = [ordered]@{
        'Battery Tooltip'='tools\Manage.ps1'
    }
    # Check ownership of every existing shortcut before changing any of them.
    $owned = @{}
    foreach ($title in $entries.Keys) {
        $path = Join-Path $MenuRoot "$title.lnk"
        $owned[$title] = $false
        if (Test-Path -LiteralPath $path) {
            $link = $shell.CreateShortcut($path)
            $owned[$title] = $link.TargetPath -eq $launcher -and -not $link.Arguments
            if ($Mode -eq 'Enable' -and -not $owned[$title]) {
                throw 'Another Battery Tooltip directory owns the Start menu shortcuts. Uninstall that copy before installing this one.'
            }
        }
    }
    if ($Mode -eq 'Enable') {
        New-Item -ItemType Directory -Path $MenuRoot -Force | Out-Null
        foreach ($title in $entries.Keys) {
            $link = $shell.CreateShortcut((Join-Path $MenuRoot "$title.lnk"))
            $link.TargetPath = $launcher
            $link.Arguments = ''
            $link.WindowStyle = 7
            $link.WorkingDirectory = $ProjectRoot
            $link.Description = $title
            $icon = Join-Path $ProjectRoot 'assets\battery-tooltip.ico'
            if (Test-Path -LiteralPath $icon) { $link.IconLocation = "$icon,0" }
            $link.Save()
            [BatteryTooltip.ShellIdentity]::ConfigureShortcut((Join-Path $MenuRoot "$title.lnk"))
        }
        return $true
    }
    if ($Mode -eq 'Disable') {
        foreach ($title in $entries.Keys) {
            if ($owned[$title]) { Remove-Item -LiteralPath (Join-Path $MenuRoot "$title.lnk") }
        }
        if ((Test-Path -LiteralPath $MenuRoot) -and @(Get-ChildItem -LiteralPath $MenuRoot -Force).Count -eq 0) {
            Remove-Item -LiteralPath $MenuRoot
        }
        return $false
    }
    return @($owned.Values | Where-Object { $_ }).Count -eq $entries.Count
}
