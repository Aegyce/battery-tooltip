param([switch]$VerifyLayout)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ShellIdentity.ps1')
if (-not $VerifyLayout) { [BatteryTooltip.ShellIdentity]::InitializeProcess() }
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
. (Join-Path $PSScriptRoot 'WriteConfig.ps1')
. (Join-Path $PSScriptRoot 'Runtime.ps1')
. (Join-Path $PSScriptRoot 'StartupConfig.ps1')
. (Join-Path $PSScriptRoot 'ManagerProcess.ps1')
. (Join-Path $PSScriptRoot 'WatchControl.ps1')
$projectRoot = Split-Path -Parent $PSScriptRoot
$allStrings = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Manager.strings.json')) | ConvertFrom-Json
$configPath = Join-Path $projectRoot 'runtime\windhawk\AppData\Engine\Mods\local@battery-tooltip.ini'
$config = Read-ModConfig $configPath
$language = [regex]::Match($config,'(?m)^language=([^\r\n]+)').Groups[1].Value.Trim()
$uiLanguage = [BatteryTooltip.NativeTaskbar]::GetUserDefaultUILanguage()
$chinese = $language -eq 'zh-CN' -or ($language -eq 'auto' -and ($uiLanguage -band 0x3ff) -eq 0x04)
$strings = if ($chinese) { $allStrings.zh } else { $allStrings.en }
$window = [Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Manager.xaml')))
$icon = Join-Path $projectRoot 'assets\battery-tooltip.ico'
if (Test-Path -LiteralPath $icon) { $window.Icon = [Windows.Media.Imaging.BitmapFrame]::Create([Uri]::new($icon)) }
if (-not $VerifyLayout) {
    $window.Add_SourceInitialized({
        $script:managerHandle = [Windows.Interop.WindowInteropHelper]::new($window).Handle
        [BatteryTooltip.ShellIdentity]::ConfigureWindow($script:managerHandle,$projectRoot)
    })
    $window.Add_Closing({ [BatteryTooltip.ShellIdentity]::ClearWindow($script:managerHandle) })
}
$stateLabel = $window.FindName('StateLabel')
$startupCheck = $window.FindName('StartupCheck')
$actionButton = $window.FindName('ActionButton')
$stopButton = $window.FindName('StopButton')
$uninstallButton = $window.FindName('UninstallButton')
$closeButton = $window.FindName('CloseButton')
$updateButton = $window.FindName('UpdateButton')
$errorLabel = $window.FindName('ErrorLabel')
$startupCheck.Content = $strings.startup
$stopButton.Content = $strings.stop
$uninstallButton.Content = $strings.uninstall
$closeButton.Content = $strings.close
$updateButton.Content = $strings.update
$script:refreshing = $false
$script:operation = $null
$script:closeAfterOperation = $false
$script:running = $false

function Update-ManagerStatus {
    try {
        $text = Read-ModConfig $configPath
        $library = [regex]::Match($text,'(?m)^LibraryFileName=([^\r\n]+)').Groups[1].Value.Trim()
        $version = [regex]::Match($text,'(?m)^Version=([^\r\n]+)').Groups[1].Value.Trim()
        $state = Get-BatteryTooltipRuntime $projectRoot $library
        $script:running = $state.HookReady
        $recovering = -not $script:running -and (Get-BatteryTooltipWatchRunning $projectRoot)
        $label = if ($script:running) { $strings.running } elseif ($recovering) { $strings.recovering } else { $strings.stopped }
        $stateLabel.Text = '{0} | v{1}' -f $label,$version
        $stateLabel.Foreground = if ($script:running) { [Windows.Media.Brushes]::ForestGreen } else { [Windows.Media.Brushes]::DimGray }
        $actionButton.Content = if ($script:running -or $recovering) { $strings.restart } else { $strings.start }
        $script:refreshing = $true
        $startupCheck.IsChecked = Set-BatteryTooltipStartup $projectRoot Status
        $script:refreshing = $false
        $stopButton.IsEnabled = $script:running -or $recovering
        if (-not $script:running -and $state.LastError) {
            $errorLabel.Text = $state.LastError
            $errorLabel.Visibility = 'Visible'
        }
    } catch {
        $errorLabel.Text = $_.Exception.Message
        $errorLabel.Visibility = 'Visible'
    }
}

function Start-ManagerOperation([string]$ScriptName,[string]$Arguments = '',[bool]$CloseAfter = $false) {
    if ($script:operation) { return }
    $logDirectory = Join-Path $projectRoot 'artifacts'
    try {
        $script:operation = Start-BatteryTooltipManagerProcess (Join-Path $PSScriptRoot $ScriptName) $Arguments $logDirectory
        $script:closeAfterOperation = $CloseAfter
        foreach ($control in @($startupCheck,$actionButton,$stopButton,$uninstallButton,$updateButton)) { $control.IsEnabled = $false }
        $stateLabel.Text = switch ($ScriptName) {
            'Update.ps1' { $strings.updateChecking }
            'Startup.ps1' { $strings.savingStartup }
            'Rollback.ps1' { $strings.stopping }
            'Uninstall.ps1' { $strings.uninstalling }
            default { if ($actionButton.Content -eq $strings.restart) { $strings.restarting } else { $strings.starting } }
        }
        $errorLabel.Visibility = 'Collapsed'
    } catch {
        $errorLabel.Text = $_.Exception.Message
        $errorLabel.Visibility = 'Visible'
    }
}

$actionButton.Add_Click({ Start-ManagerOperation 'Restart.ps1' })
$stopButton.Add_Click({ Start-ManagerOperation 'Rollback.ps1' '-KeepAutoStart' })
$uninstallButton.Add_Click({ Start-ManagerOperation 'Uninstall.ps1' '' $true })
$closeButton.Add_Click({ $window.Close() })
$updateButton.Add_Click({ Start-ManagerOperation 'Update.ps1' })
$startupChanged = {
    if (-not $script:refreshing) {
        $mode = if ($startupCheck.IsChecked) { 'Enable' } else { 'Disable' }
        Start-ManagerOperation 'Startup.ps1' "-Mode $mode"
    }
}
$startupCheck.Add_Checked($startupChanged)
$startupCheck.Add_Unchecked($startupChanged)
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({
    if ($script:operation) {
        if (-not $script:operation.HasExited) { return }
        $script:operation.WaitForExit()
        $success = $script:operation.ExitCode -eq 0
        $script:operation.Dispose()
        $script:operation = $null
        if ($success -and $script:closeAfterOperation) { $window.Close(); return }
        foreach ($control in @($startupCheck,$actionButton,$stopButton,$uninstallButton,$updateButton)) { $control.IsEnabled = $true }
        if (-not $success) { $errorLabel.Text = $strings.failed; $errorLabel.Visibility = 'Visible' }
    }
    Update-ManagerStatus
})
$window.Add_Closed({ $timer.Stop() })
if ($VerifyLayout) {
    $version = [regex]::Match($config,'(?m)^Version=([^\r\n]+)').Groups[1].Value.Trim()
    $stateLabel.Text = '{0} | v{1}' -f $strings.stopped,$version
    $actionButton.Content = $strings.start
    $content = $window.Content
    $content.Measure([Windows.Size]::new(292,[double]::PositiveInfinity))
    $size = [Windows.Size]::new(292,$content.DesiredSize.Height)
    $content.Arrange([Windows.Rect]::new([Windows.Point]::new(0,0),$size))
    $content.UpdateLayout()
    $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new([int]$size.Width,[int]$size.Height,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($content)
    $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $path = Join-Path $projectRoot 'artifacts\manager.png'
    $stream = [IO.File]::Create($path)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
    Write-Host "Manager content: $($size.Width) x $($size.Height). Saved $path"
} else {
    Update-ManagerStatus
    $timer.Start()
    $window.ShowDialog() | Out-Null
}
