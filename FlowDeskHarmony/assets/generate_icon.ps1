Add-Type -AssemblyName System.Drawing

$assetDir = "D:\AI\opencode\FlowDeskHarmony\assets"
$fgPath = "$assetDir\icon_foreground.png"
$bgPath = "$assetDir\icon_background.png"
$previewDir = "$assetDir\previews"

if (-not (Test-Path $previewDir)) { New-Item -ItemType Directory -Path $previewDir -Force | Out-Null }

$Size = 1024
$bmp = New-Object System.Drawing.Bitmap $Size, $Size
$gfx = [System.Drawing.Graphics]::FromImage($bmp)
$gfx.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gfx.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$gfx.Clear([System.Drawing.Color]::Transparent)

$blueBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 10, 89, 247))
$whiteBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)

# 1. 圆角矩形主背景（蓝色） rx=200
$bg = New-Object System.Drawing.Drawing2D.GraphicsPath
$bg.AddArc(0, 0, 400, 400, 180, 90)
$bg.AddArc(624, 0, 400, 400, 270, 90)
$bg.AddArc(624, 624, 400, 400, 0, 90)
$bg.AddArc(0, 624, 400, 400, 90, 90)
$bg.CloseFigure()
$gfx.FillPath($blueBrush, $bg)

# 2. 显示器外框（白色填充圆角矩形 + 蓝色挖空内部） rx=28
$monOut = New-Object System.Drawing.Drawing2D.GraphicsPath
$monOut.AddArc(180, 300, 56, 56, 180, 90)
$monOut.AddArc(544, 300, 56, 56, 270, 90)
$monOut.AddArc(544, 544, 56, 56, 0, 90)
$monOut.AddArc(180, 544, 56, 56, 90, 90)
$monOut.CloseFigure()
$gfx.FillPath($whiteBrush, $monOut)

$monIn = New-Object System.Drawing.Drawing2D.GraphicsPath
$monIn.AddArc(216, 336, 32, 32, 180, 90)
$monIn.AddArc(532, 336, 32, 32, 270, 90)
$monIn.AddArc(532, 532, 32, 32, 0, 90)
$monIn.AddArc(216, 532, 32, 32, 90, 90)
$monIn.CloseFigure()
$gfx.FillPath($blueBrush, $monIn)

# 3. 显示器底部支架
$gfx.FillRectangle($whiteBrush, 360, 600, 60, 40)
$gfx.FillRectangle($whiteBrush, 280, 640, 220, 28)

# 4. 连接箭头（从显示器指向手机）
$arrowPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 36
$arrowPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$arrowPen.EndCap = [System.Drawing.Drawing2D.LineCap]::ArrowAnchor
$arrowPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
$gfx.DrawLine($arrowPen, 624, 450, 738, 450)

# 5. 手机（白色填充圆角矩形 + 蓝色挖空） rx=26
$phOut = New-Object System.Drawing.Drawing2D.GraphicsPath
$phOut.AddArc(740, 360, 52, 52, 180, 90)
$phOut.AddArc(828, 360, 52, 52, 270, 90)
$phOut.AddArc(828, 588, 52, 52, 0, 90)
$phOut.AddArc(740, 588, 52, 52, 90, 90)
$phOut.CloseFigure()
$gfx.FillPath($whiteBrush, $phOut)

$phIn = New-Object System.Drawing.Drawing2D.GraphicsPath
$phIn.AddArc(766, 416, 28, 28, 180, 90)
$phIn.AddArc(826, 416, 28, 28, 270, 90)
$phIn.AddArc(826, 568, 28, 28, 0, 90)
$phIn.AddArc(766, 568, 28, 28, 90, 90)
$phIn.CloseFigure()
$gfx.FillPath($blueBrush, $phIn)

# 6. 手机听筒
$gfx.FillRectangle($whiteBrush, 790, 380, 40, 10)
# 7. 手机 Home 键
$gfx.FillEllipse($whiteBrush, 798, 608, 24, 24)

$bmp.Save($fgPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
$gfx.Dispose()
Write-Host "[OK] foreground -> $fgPath"

# 背景
$bmp2 = New-Object System.Drawing.Bitmap $Size, $Size
$gfx2 = [System.Drawing.Graphics]::FromImage($bmp2)
$gfx2.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$gfx2.Clear([System.Drawing.Color]::FromArgb(255, 10, 89, 247))
$bmp2.Save($bgPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp2.Dispose()
$gfx2.Dispose()
Write-Host "[OK] background -> $bgPath"

# 预览
$source = [System.Drawing.Image]::FromFile((Resolve-Path $fgPath))
foreach ($s in @(48, 96, 144, 192, 256, 512)) {
    $b = New-Object System.Drawing.Bitmap $s, $s
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($source, 0, 0, $s, $s)
    $out = "$previewDir\icon_${s}.png"
    $b.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    $b.Dispose()
    $g.Dispose()
    Write-Host "[OK] preview ${s}px -> $out"
}
$source.Dispose()
Write-Host "`nDone."
