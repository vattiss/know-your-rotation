param([string]$OutDir)
Add-Type -AssemblyName System.Drawing

$S = 1024
$bmp = New-Object System.Drawing.Bitmap $S, $S, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.Clear([System.Drawing.Color]::Transparent)

function RoundRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
	$p = New-Object System.Drawing.Drawing2D.GraphicsPath
	$d = $r * 2
	$p.AddArc($x, $y, $d, $d, 180, 90)
	$p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
	$p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
	$p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
	$p.CloseFigure()
	return $p
}

# Outer glow: many soft gold strokes around the button.
$btnX = 150; $btnY = 150; $btnW = 724; $btnR = 110
for ($i = 70; $i -ge 1; $i -= 2) {
	$alpha = [int](70 * (1 - $i / 72.0))
	$pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb($alpha, 255, 196, 60)), ($i * 2)
	$pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
	$path = RoundRect $btnX $btnY $btnW $btnW $btnR
	$g.DrawPath($pen, $path)
	$pen.Dispose(); $path.Dispose()
}

# Button body: dark blue-slate gradient.
$body = RoundRect $btnX $btnY $btnW $btnW $btnR
$grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.PointF 0, $btnY), (New-Object System.Drawing.PointF 0, ($btnY + $btnW)), ([System.Drawing.Color]::FromArgb(255, 34, 48, 78)), ([System.Drawing.Color]::FromArgb(255, 12, 16, 28))
$g.FillPath($grad, $body)

# Gold bevel frame.
$frameOuter = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 120, 82, 22)), 46
$frameOuter.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
$g.DrawPath($frameOuter, $body)
$frameInner = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 255, 214, 102)), 22
$frameInner.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
$g.DrawPath($frameInner, $body)

# Open book.
$cx = 512
$bookTop = 560; $bookBottom = 760; $bookHalf = 250
$pageBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 245, 232, 200))
$edgePen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 120, 82, 22)), 14
$edgePen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
foreach ($side in @(-1, 1)) {
	$p = New-Object System.Drawing.Drawing2D.GraphicsPath
	$outerX = $cx + $side * $bookHalf
	$p.AddBezier($cx, ($bookTop + 20), ($cx + $side * 80), ($bookTop - 30), ($outerX - $side * 90), ($bookTop - 40), $outerX, ($bookTop - 10))
	$p.AddLine($outerX, ($bookTop - 10), $outerX, ($bookBottom - 20))
	$p.AddBezier($outerX, ($bookBottom - 20), ($outerX - $side * 90), ($bookBottom - 50), ($cx + $side * 80), ($bookBottom - 40), $cx, ($bookBottom + 10))
	$p.CloseFigure()
	$g.FillPath($pageBrush, $p)
	$g.DrawPath($edgePen, $p)
	$p.Dispose()
}
$spine = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 120, 82, 22)), 12
$g.DrawLine($spine, $cx, ($bookTop + 20), $cx, ($bookBottom + 10))

# Glowing up chevron above the book (leveling / learning).
for ($i = 40; $i -ge 1; $i -= 2) {
	$alpha = [int](90 * (1 - $i / 42.0))
	$pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb($alpha, 255, 220, 120)), (60 + $i * 2)
	$pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
	$pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
	$pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
	$g.DrawLines($pen, [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF 352, 470), (New-Object System.Drawing.PointF 512, 310), (New-Object System.Drawing.PointF 672, 470)))
	$pen.Dispose()
}
$chev = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 255, 214, 102)), 64
$chev.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$chev.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$chev.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
$g.DrawLines($chev, [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF 352, 470), (New-Object System.Drawing.PointF 512, 310), (New-Object System.Drawing.PointF 672, 470)))
$chevCore = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 255, 248, 220)), 24
$chevCore.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$chevCore.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$chevCore.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
$g.DrawLines($chevCore, [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF 352, 470), (New-Object System.Drawing.PointF 512, 310), (New-Object System.Drawing.PointF 672, 470)))

$g.Dispose()
New-Item -ItemType Directory -Force $OutDir | Out-Null
$bmp.Save((Join-Path $OutDir "logo-1024.png"), [System.Drawing.Imaging.ImageFormat]::Png)

function SaveScaled([System.Drawing.Bitmap]$src, [int]$size, [string]$path) {
	$dst = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
	$gg = [System.Drawing.Graphics]::FromImage($dst)
	$gg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
	$gg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
	$gg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
	$gg.Clear([System.Drawing.Color]::Transparent)
	$gg.DrawImage($src, 0, 0, $size, $size)
	$gg.Dispose()
	$dst.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
	return $dst
}
$b400 = SaveScaled $bmp 400 (Join-Path $OutDir "logo-400.png")
$b128 = SaveScaled $bmp 128 (Join-Path $OutDir "logo-128.png")
$b32 = SaveScaled $bmp 32 (Join-Path $OutDir "logo-32.png")
$b400.Dispose(); $b32.Dispose()

# 128x128 32-bit uncompressed TGA for the game (bottom-left origin).
$w = 128; $h = 128
$bytes = New-Object byte[] (18 + $w * $h * 4)
$bytes[2] = 2
$bytes[12] = $w -band 255; $bytes[13] = $w -shr 8
$bytes[14] = $h -band 255; $bytes[15] = $h -shr 8
$bytes[16] = 32
$bytes[17] = 8
$o = 18
for ($y = $h - 1; $y -ge 0; $y--) {
	for ($x = 0; $x -lt $w; $x++) {
		$c = $b128.GetPixel($x, $y)
		$bytes[$o] = $c.B; $bytes[$o + 1] = $c.G; $bytes[$o + 2] = $c.R; $bytes[$o + 3] = $c.A
		$o += 4
	}
}
[System.IO.File]::WriteAllBytes((Join-Path $OutDir "logo.tga"), $bytes)
$b128.Dispose(); $bmp.Dispose()
"done"
