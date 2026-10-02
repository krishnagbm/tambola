Add-Type -AssemblyName System.Drawing
$srcPath = "c:\dev\Tambola\docs\marketting\Mascat\DabHousie 90-Ball Bingo Mascot Banner.png"
$bmp = [System.Drawing.Bitmap]::FromFile($srcPath)

$scales = @(1, 2, 3, 4)
foreach ($s in $scales) {
    $targetW = [int](180 * $s)
    $targetH = [int]($targetW * ($bmp.Height / $bmp.Width))
    $resized = New-Object System.Drawing.Bitmap $targetW, $targetH
    $g = [System.Drawing.Graphics]::FromImage($resized)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($bmp, 0, 0, $targetW, $targetH)
    
    $lightPath = "c:\dev\Tambola\web\splash\img\light-$($s)x.png"
    $darkPath = "c:\dev\Tambola\web\splash\img\dark-$($s)x.png"
    
    $resized.Save($lightPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $resized.Save($darkPath, [System.Drawing.Imaging.ImageFormat]::Png)
    
    $g.Dispose()
    $resized.Dispose()
    Write-Host "Generated $lightPath and $darkPath"
}

$bmp.Dispose()
Write-Host "All splash images updated!"
