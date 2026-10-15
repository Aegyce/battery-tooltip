param([string]$Source = '',[string]$Destination = '')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
if (-not $Source) { $Source = Join-Path $root 'assets\battery-tooltip.png' }
if (-not $Destination) { $Destination = Join-Path $root 'assets\battery-tooltip.ico' }
$sourceImage = [Drawing.Image]::FromFile($Source)
try {
    $frames = foreach ($size in @(16,20,24,32,40,48,64,128,256)) {
        $bitmap = [Drawing.Bitmap]::new($size,$size,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        $stream = [IO.MemoryStream]::new()
        try {
            $graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
            $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.DrawImage($sourceImage,0,0,$size,$size)
            $bitmap.Save($stream,[Drawing.Imaging.ImageFormat]::Png)
            [pscustomobject]@{Size=$size;Data=$stream.ToArray()}
        } finally { $stream.Dispose();$graphics.Dispose();$bitmap.Dispose() }
    }
    $output = [IO.File]::Create($Destination)
    $writer = [IO.BinaryWriter]::new($output)
    try {
        $writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]$frames.Count)
        $offset = 6 + 16 * $frames.Count
        foreach ($frame in $frames) {
            $edge = if ($frame.Size -eq 256) { 0 } else { $frame.Size }
            $writer.Write([byte]$edge);$writer.Write([byte]$edge)
            $writer.Write([byte]0);$writer.Write([byte]0)
            $writer.Write([uint16]1);$writer.Write([uint16]32)
            $writer.Write([uint32]$frame.Data.Length);$writer.Write([uint32]$offset)
            $offset += $frame.Data.Length
        }
        foreach ($frame in $frames) { $writer.Write([byte[]]$frame.Data) }
    } finally { $writer.Dispose();$output.Dispose() }
} finally { $sourceImage.Dispose() }
Write-Host "Windows icon saved: $Destination"
