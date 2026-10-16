function Get-BatteryTooltipVersion([string]$Text) {
    if ($Text -notmatch '^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') { throw 'Invalid release version.' }
    return [version]$Text.TrimStart('v')
}

function Get-BatteryTooltipUpdatePlan($Release,[string]$CurrentVersion) {
    if ($Release.draft -or $Release.prerelease) { throw 'The release is not a stable public release.' }
    $latest = Get-BatteryTooltipVersion $Release.tag_name
    $current = Get-BatteryTooltipVersion $CurrentVersion
    $name = "BatteryTooltip-$latest.zip"
    $assets = @{}
    foreach ($required in @($name,'SHA256SUMS.txt')) {
        $found = @($Release.assets | Where-Object name -eq $required)
        if ($found.Count -ne 1) { throw "Missing or duplicate release asset: $required" }
        $uri = [uri]$found[0].browser_download_url
        $expected = '/Aegyce/battery-tooltip/releases/download/' + $Release.tag_name + '/' + $required
        if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'https' -or $uri.Host -ne 'github.com' -or
            -not $uri.IsDefaultPort -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.AbsolutePath -cne $expected) {
            throw 'The release contains an unexpected download address.'
        }
        $assets[$required] = $uri.AbsoluteUri
    }
    [pscustomobject]@{CurrentVersion=$current.ToString();Version=$latest.ToString();Available=($latest -gt $current);
        PackageName=$name;PackageUrl=$assets[$name];ChecksumUrl=$assets['SHA256SUMS.txt']}
}

function Write-BatteryTooltipUpdateLog([string]$ProjectRoot,[string]$Message) {
    $directory = Join-Path $ProjectRoot 'artifacts'
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    [IO.File]::AppendAllText((Join-Path $directory 'update.log'),"$(Get-Date -Format o) $Message`r`n")
}

function Assert-BatteryTooltipUpdateJob([string]$ProjectRoot,[string]$JobRoot) {
    $root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
    $cache = Join-Path $root 'artifacts\update-cache'
    $job = [IO.Path]::GetFullPath($JobRoot).TrimEnd('\')
    if ([IO.Path]::GetDirectoryName($job) -ne $cache -or [IO.Path]::GetFileName($job) -notmatch '^[a-f0-9]{32}$') {
        throw 'Refusing to access an update directory outside this installation cache.'
    }
    foreach ($path in @($root,(Join-Path $root 'artifacts'),$cache,$job)) {
        if ((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Update directories must not be symbolic links or junctions.'
        }
    }
    $marker = Get-Content -LiteralPath (Join-Path $job 'owner.json') -Raw | ConvertFrom-Json
    if ($marker.projectRoot -ne $root -or $marker.id -ne [IO.Path]::GetFileName($job)) { throw 'Update directory ownership is invalid.' }
    return $job
}

function New-BatteryTooltipUpdateJob([string]$ProjectRoot) {
    $root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
    $id = [Guid]::NewGuid().ToString('N')
    $job = Join-Path $root "artifacts\update-cache\$id"
    foreach ($path in @($root,(Join-Path $root 'artifacts'),(Join-Path $root 'artifacts\update-cache'))) {
        if ((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Update cache must not use a junction.' }
    }
    New-Item -ItemType Directory -Path $job -Force | Out-Null
    @{projectRoot=$root;id=$id;processId=$PID;processStart=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $job 'owner.json') -Encoding UTF8
    return $job
}

function Remove-BatteryTooltipUpdateJob([string]$ProjectRoot,[string]$JobRoot) {
    if (-not (Test-Path -LiteralPath $JobRoot)) { return }
    $job = Assert-BatteryTooltipUpdateJob $ProjectRoot $JobRoot
    # A nested junction must never turn cache cleanup into deletion elsewhere.
    $stack = [Collections.Generic.Stack[string]]::new()
    $stack.Push($job)
    while ($stack.Count) {
        foreach ($item in Get-ChildItem -LiteralPath $stack.Pop() -Force) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing to clean a cache containing a junction.' }
            if ($item.PSIsContainer) { $stack.Push($item.FullName) }
        }
    }
    for ($attempt=0;$attempt -lt 6;$attempt++) {
        try { Remove-Item -LiteralPath $job -Recurse -Force; return }
        catch { if ($attempt -eq 5) { throw }; Start-Sleep -Milliseconds 250 }
    }
}

function Clear-BatteryTooltipStaleUpdates([string]$ProjectRoot) {
    $cache = Join-Path $ProjectRoot 'artifacts\update-cache'
    if (-not (Test-Path -LiteralPath $cache)) { return }
    foreach ($directory in Get-ChildItem -LiteralPath $cache -Directory) {
        try {
            $job = Assert-BatteryTooltipUpdateJob $ProjectRoot $directory.FullName
            $owner = Get-Content -LiteralPath (Join-Path $job 'owner.json') -Raw | ConvertFrom-Json
            $process = Get-Process -Id $owner.processId -ErrorAction SilentlyContinue
            if (-not $process -or $process.StartTime.ToUniversalTime().Ticks -ne $owner.processStart) { Remove-BatteryTooltipUpdateJob $ProjectRoot $job }
        } catch { Write-BatteryTooltipUpdateLog $ProjectRoot "Cache cleanup deferred: $($_.Exception.Message)" }
    }
}

function Get-BatteryTooltipPackageFiles([string]$Root) {
    $names = @('VERSION','README.md','LICENSE','battery-tooltip.wh.cpp','Setup.cmd','Install.cmd','Manage.cmd','Start.cmd','Restart.cmd','Rollback.cmd','Status.cmd','Uninstall.cmd')
    foreach ($name in $names) { if (Test-Path -LiteralPath (Join-Path $Root $name) -PathType Leaf) { $name } }
    foreach ($name in @('tools','tests','assets','Precompiled')) {
        $directory = Join-Path $Root $name
        if (-not (Test-Path -LiteralPath $directory)) { continue }
        $stack = [Collections.Generic.Stack[string]]::new(); $stack.Push($directory)
        while ($stack.Count) {
            $parent = Get-Item -LiteralPath $stack.Pop()
            if ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Application files must not use junctions.' }
            foreach ($item in Get-ChildItem -LiteralPath $parent.FullName -Force) {
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Application files must not use symbolic links.' }
                if ($item.PSIsContainer) { $stack.Push($item.FullName) }
                else { $item.FullName.Substring([IO.Path]::GetFullPath($Root).TrimEnd('\').Length+1) }
            }
        }
    }
}

function Expand-BatteryTooltipUpdate([string]$Archive,[string]$Destination,[string]$Version) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        $total = [long]0
        if ($zip.Entries.Count -gt 10000) { throw 'Update archive has too many entries.' }
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $rootFiles = @('VERSION','README.md','LICENSE','battery-tooltip.wh.cpp','Setup.cmd','Install.cmd','Manage.cmd','Start.cmd','Restart.cmd','Rollback.cmd','Status.cmd','Uninstall.cmd')
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace('\','/').TrimEnd('/')
            $parts = $name.Split('/')
            if (-not $name -or $name.Contains(':') -or $parts -contains '..' -or $parts -contains '.' -or $parts -contains '' -or
                @($parts | Where-Object { $_ -match '[. ]$|^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)' }).Count -gt 0 -or
                $name.StartsWith('/') -or ($parts.Count -eq 1 -and $name -notin $rootFiles -and $name -notin @('tools','tests','assets','Precompiled')) -or
                ($parts.Count -gt 1 -and $parts[0] -notin @('tools','tests','assets','Precompiled')) -or
                (($entry.ExternalAttributes -shr 16) -band 0xf000) -eq 0xa000 -or -not $seen.Add($name)) { throw "Invalid update archive entry: $name" }
            $total += $entry.Length
            if ($total -gt 268435456) { throw 'Update archive exceeds the extracted size limit.' }
        }
    } finally { $zip.Dispose() }
    Expand-Archive -LiteralPath $Archive -DestinationPath $Destination
    foreach ($required in @('VERSION','Precompiled\manifest.json','tools\Start.ps1','tools\Rollback.ps1','tools\InstallPackage.ps1','tools\Manage.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Destination $required) -PathType Leaf)) { throw "Update package is incomplete: $required" }
    }
    if ([IO.File]::ReadAllText((Join-Path $Destination 'VERSION')).Trim() -ne $Version) { throw 'Update package version is inconsistent.' }
    $manifest = Get-Content -LiteralPath (Join-Path $Destination 'Precompiled\manifest.json') -Raw | ConvertFrom-Json
    if ($manifest.version -ne $Version) { throw 'Precompiled update version is inconsistent.' }
    foreach ($entry in $manifest.files) {
        if ($entry.name -match '[/\\:]' -or $entry.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid precompiled update manifest.' }
        if ((Get-FileHash -LiteralPath (Join-Path $Destination "Precompiled\$($entry.name)") -Algorithm SHA256).Hash -ne $entry.sha256) { throw 'Precompiled update checksum mismatch.' }
    }
}

function Get-BatteryTooltipUpdateSnapshotFiles([string]$ProjectRoot) {
    Get-BatteryTooltipPackageFiles $ProjectRoot
    foreach ($name in @('runtime','runtime\windhawk','runtime\windhawk\AppData','runtime\windhawk\AppData\Engine',
        'runtime\windhawk\AppData\Engine\Mods','runtime\windhawk\AppData\Engine\Mods\64',
        'runtime\windhawk\AppData\Engine\ModsWritable','runtime\windhawk\AppData\ModsSource')) {
        $directory = Join-Path $ProjectRoot $name
        if ((Test-Path -LiteralPath $directory) -and ((Get-Item -LiteralPath $directory).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Runtime directories must not use junctions.'
        }
    }
    foreach ($name in @('runtime\windhawk\AppData\Engine\Mods\local@battery-tooltip.ini',
        'runtime\windhawk\AppData\Engine\Mods\local@battery-tooltip.ini.bak',
        'runtime\windhawk\AppData\Engine\ModsWritable\local@battery-tooltip.ini',
        'runtime\windhawk\AppData\ModsSource\local@battery-tooltip.wh.cpp')) {
        if (Test-Path -LiteralPath (Join-Path $ProjectRoot $name) -PathType Leaf) { $name }
    }
    $libraries = Join-Path $ProjectRoot 'runtime\windhawk\AppData\Engine\Mods\64'
    if (Test-Path -LiteralPath $libraries) {
        foreach ($item in Get-ChildItem -LiteralPath $libraries -File) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Runtime libraries must not be symbolic links.' }
            'runtime\windhawk\AppData\Engine\Mods\64\' + $item.Name
        }
    }
}

function Copy-BatteryTooltipUpdateFiles([string]$Source,[string]$Destination,[string[]]$Files) {
    foreach ($file in $Files) {
        $target = Join-Path $Destination $file
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $Source $file) -Destination $target -Force
    }
}

function Get-BatteryTooltipUpdateActions {
    @{
        State = {
            param($root)
            $text = Read-ModConfig (Join-Path $root 'runtime\windhawk\AppData\Engine\Mods\local@battery-tooltip.ini')
            @{Running=($text -match '(?m)^Disabled=0\r?$');Startup=(Set-BatteryTooltipStartup $root Status);
                Menu=(Set-BatteryTooltipMenu $root Status);Version=([regex]::Match($text,'(?m)^Version=([^\r\n]+)').Groups[1].Value.Trim())}
        }
        Stop = {param($root) & (Join-Path $root 'tools\Rollback.ps1') -KeepAutoStart}
        Install = {param($root) . (Join-Path $root 'tools\InstallPackage.ps1'); Install-BatteryTooltipPackage $root}
        Start = {param($root) & (Join-Path $root 'tools\Start.ps1')}
        Preferences = {
            param($root,$state)
            $mode = if ($state.Startup) {'Enable'} else {'Disable'}
            Set-BatteryTooltipStartup $root $mode | Out-Null
            $mode = if ($state.Menu) {'Enable'} else {'Disable'}
            Set-BatteryTooltipMenu $root $mode | Out-Null
        }
    }
}

function Install-BatteryTooltipPreparedUpdate([string]$ProjectRoot,[string]$JobRoot,[hashtable]$Actions = $null) {
    . (Join-Path $PSScriptRoot 'OperationLock.ps1')
    $operation = Enter-BatteryTooltipOperation $ProjectRoot
    try {
        $job = Assert-BatteryTooltipUpdateJob $ProjectRoot $JobRoot
        $plan = Get-Content -LiteralPath (Join-Path $job 'plan.json') -Raw | ConvertFrom-Json
        $payload = Join-Path $job 'payload'
        $backup = Join-Path $job 'backup'
        $changed = $false
        $state = $null
        try {
            if (-not $Actions) { $Actions = Get-BatteryTooltipUpdateActions }
            $state = & $Actions.State $ProjectRoot
            if ($state.Version -ne $plan.CurrentVersion -or
                (Get-BatteryTooltipVersion $plan.Version) -le (Get-BatteryTooltipVersion $state.Version)) { throw 'Installed version changed after checking for updates. Check again.' }
            $oldFiles = @(Get-BatteryTooltipUpdateSnapshotFiles $ProjectRoot)
            Copy-BatteryTooltipUpdateFiles $ProjectRoot $backup $oldFiles
            & $Actions.Stop $ProjectRoot | Out-Null
            $changed = $true
            Copy-BatteryTooltipUpdateFiles $payload $ProjectRoot @(Get-BatteryTooltipPackageFiles $payload)
            & $Actions.Install $ProjectRoot | Out-Null
            if ($state.Running) { & $Actions.Start $ProjectRoot | Out-Null }
            & $Actions.Preferences $ProjectRoot $state | Out-Null
            Write-BatteryTooltipUpdateLog $ProjectRoot "Installed update $($plan.CurrentVersion) -> $($plan.Version)"
            return $plan.Version
        } catch {
            $failure = $_
            if ($changed) {
                try {
                    & $Actions.Stop $ProjectRoot | Out-Null
                    foreach ($file in @(Get-BatteryTooltipUpdateSnapshotFiles $ProjectRoot)) {
                        if ($file -notin $oldFiles) { Remove-Item -LiteralPath (Join-Path $ProjectRoot $file) -Force }
                    }
                    Copy-BatteryTooltipUpdateFiles $backup $ProjectRoot $oldFiles
                    if ($state.Running) { & $Actions.Start $ProjectRoot | Out-Null }
                    & $Actions.Preferences $ProjectRoot $state | Out-Null
                    Write-BatteryTooltipUpdateLog $ProjectRoot "Update failed; restored $($state.Version): $($failure.Exception.Message)"
                } catch {
                    $recovery = Join-Path $ProjectRoot ('artifacts\update-recovery\' + [IO.Path]::GetFileName($job))
                    Copy-BatteryTooltipUpdateFiles $backup $recovery $oldFiles
                    Write-BatteryTooltipUpdateLog $ProjectRoot "Automatic recovery failed: $($_.Exception.Message). Backup: $recovery"
                    throw "Update and automatic recovery failed. Backup saved at $recovery"
                }
            }
            throw $failure
        } finally {
            Remove-BatteryTooltipUpdateJob $ProjectRoot $job
        }
    } finally { Exit-BatteryTooltipOperation $operation }
}

function New-BatteryTooltipPreparedUpdate([string]$ProjectRoot,$Plan,[scriptblock]$Download) {
    $job = New-BatteryTooltipUpdateJob $ProjectRoot
    try {
        $archive = Join-Path $job $Plan.PackageName
        $checksums = Join-Path $job 'SHA256SUMS.txt'
        & $Download $Plan.ChecksumUrl $checksums
        & $Download $Plan.PackageUrl $archive
        if ((Get-Item -LiteralPath $archive).Length -gt 67108864 -or (Get-Item -LiteralPath $checksums).Length -gt 65536) { throw 'Downloaded update exceeds the size limit.' }
        $hashes = @(Get-Content -LiteralPath $checksums | ForEach-Object {
            if ($_ -match '^([a-fA-F0-9]{64})\s+\*?(.+)$' -and $matches[2] -ceq $Plan.PackageName) { $matches[1] }
        })
        if ($hashes.Count -ne 1 -or (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $hashes[0]) { throw 'Update archive checksum mismatch.' }
        Expand-BatteryTooltipUpdate $archive (Join-Path $job 'payload') $Plan.Version
        $Plan | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $job 'plan.json') -Encoding UTF8
        $worker = Join-Path $job 'worker'
        New-Item -ItemType Directory -Path $worker -Force | Out-Null
        foreach ($name in @('Update.ps1','UpdateCore.ps1','WriteConfig.ps1','Runtime.ps1','StartupConfig.ps1','NativeProcess.ps1','NativeProcess.cs','ShellIdentity.ps1','ShellIdentity.cs','Menu.ps1','InstallPackage.ps1','Manager.strings.json','OperationLock.ps1')) {
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $worker
        }
        Write-BatteryTooltipUpdateLog $ProjectRoot "Prepared update $($Plan.CurrentVersion) -> $($Plan.Version)"
        return $job
    } catch {
        Remove-BatteryTooltipUpdateJob $ProjectRoot $job
        throw
    }
}
