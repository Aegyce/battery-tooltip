if (-not ('BatteryTooltip.NativeProcess' -as [type])) {
    if ($PSVersionTable.PSEdition -eq 'Core') {
        Add-Type -Path (Join-Path $PSScriptRoot 'NativeProcess.cs')
    } else {
        Add-Type -Path (Join-Path $PSScriptRoot 'NativeProcess.cs') -ReferencedAssemblies System.dll,System.Core.dll,Microsoft.CSharp.dll
    }
}

function Start-BatteryTooltipDesktopProcess([string]$Path,[string]$Arguments,[string]$Directory) {
    [BatteryTooltip.NativeProcess]::StartViaDesktop($Path,$Arguments,$Directory)
}
