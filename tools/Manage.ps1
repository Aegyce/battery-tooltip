param([switch]$VerifyLayout)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
. (Join-Path $PSScriptRoot 'WriteConfig.ps1')
. (Join-Path $PSScriptRoot 'Runtime.ps1')
. (Join-Path $PSScriptRoot 'StartupConfig.ps1')
. (Join-Path $PSScriptRoot 'ManagerProcess.ps1')
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
$stateLabel = $window.FindName('StateLabel')
$startupCheck = $window.FindName('StartupCheck')
$actionButton = $window.FindName('ActionButton')
$stopButton = $window.FindName('StopButton')
$uninstallButton = $window.FindName('UninstallButton')
$closeButton = $window.FindName('CloseButton')
$errorLabel = $window.FindName('ErrorLabel')
$startupCheck.Content = $strings.startup
$stopButton.Content = $strings.stop
$uninstallButton.Content = $strings.uninstall
$closeButton.Content = $strings.close
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
        $label = if ($script:running) { $strings.running } else { $strings.stopped }
        $stateLabel.Text = '{0} | v{1}' -f $label,$version
        $stateLabel.Foreground = if ($script:running) { [Windows.Media.Brushes]::ForestGreen } else { [Windows.Media.Brushes]::DimGray }
        $actionButton.Content = if ($script:running) { $strings.restart } else { $strings.start }
        $script:refreshing = $true
        $startupCheck.IsChecked = Set-BatteryTooltipStartup $projectRoot Status
        $script:refreshing = $false
        $stopButton.IsEnabled = $script:running
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
        foreach ($control in @($startupCheck,$actionButton,$stopButton,$uninstallButton)) { $control.IsEnabled = $false }
        $stateLabel.Text = $strings.starting
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
        foreach ($control in @($startupCheck,$actionButton,$stopButton,$uninstallButton)) { $control.IsEnabled = $true }
        if (-not $success) { $errorLabel.Text = $strings.failed; $errorLabel.Visibility = 'Visible' }
    }
    Update-ManagerStatus
})
$window.Add_Closed({ $timer.Stop() })
Update-ManagerStatus
if ($VerifyLayout) {
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
    $timer.Start()
    $window.ShowDialog() | Out-Null
}
