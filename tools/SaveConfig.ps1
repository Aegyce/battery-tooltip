param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Source)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WriteConfig.ps1')
Write-ModConfig $Path ([IO.File]::ReadAllText($Source))
