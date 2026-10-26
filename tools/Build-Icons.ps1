$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$assets = Join-Path $root 'src/GrabPic/Assets'
$store = Join-Path $root 'submission/icons'
$package = Join-Path $root 'packaging/Assets'
foreach($path in @($assets,$store,$package,"$root/docs/images")) { New-Item -ItemType Directory -Force $path | Out-Null }
function RoundPath($x,$y,$width,$height,$radius) {
 $p = [System.Drawing.Drawing2D.GraphicsPath]::new(); $d=$radius*2
 $p.AddArc($x,$y,$d,$d,180,90); $p.AddArc($x+$width-$d,$y,$d,$d,270,90)
 $p.AddArc($x+$width-$d,$y+$height-$d,$d,$d,0,90); $p.AddArc($x,$y+$height-$d,$d,$d,90,90); $p.CloseFigure(); return ,$p
}
function DrawLogo([int]$width,[int]$height,[string]$path) {
 $factor=4; $canvas=[System.Drawing.Bitmap]::new($width*$factor,$height*$factor)
 $g=[System.Drawing.Graphics]::FromImage($canvas); $g.SmoothingMode='AntiAlias'; $g.Clear([System.Drawing.Color]::Transparent)
 $size=[Math]::Min($width,$height)*$factor; $g.TranslateTransform(($width*$factor-$size)/2,($height*$factor-$size)/2); $g.ScaleTransform($size/100,$size/100)
 $purple=[System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#A294FA'))
 $shape=RoundPath 2 2 96 96 24; $g.FillPath($purple,$shape); $shape.Dispose()
 $camera=[System.Drawing.Drawing2D.GraphicsPath]::new()
 $camera.AddLine(34,33,40,24); $camera.AddLine(40,24,60,24); $camera.AddLine(60,24,66,33); $camera.AddLine(66,33,74,33)
 $camera.AddArc(68,33,14,14,270,90); $camera.AddLine(82,40,82,68); $camera.AddArc(68,61,14,14,0,90)
 $camera.AddLine(75,75,25,75); $camera.AddArc(18,61,14,14,90,90); $camera.AddLine(18,68,18,40); $camera.AddArc(18,33,14,14,180,90); $camera.CloseFigure()
 $pen=[System.Drawing.Pen]::new([System.Drawing.Color]::White,5.5); $pen.LineJoin='Round'; $g.DrawPath($pen,$camera); $g.DrawEllipse($pen,37,41,26,26)
 $g.Dispose(); $pen.Dispose(); $camera.Dispose(); $purple.Dispose()
 $output=[System.Drawing.Bitmap]::new($width,$height); $down=[System.Drawing.Graphics]::FromImage($output); $down.InterpolationMode='HighQualityBicubic'; $down.DrawImage($canvas,0,0,$width,$height); $down.Dispose(); $canvas.Dispose()
 $output.Save($path,[System.Drawing.Imaging.ImageFormat]::Png); $output.Dispose()
}
$sizes=@(16,20,24,28,32,36,40,44,48,60,64,72,80,96,128,150,192,256,300,512,1024)
foreach($size in $sizes) { DrawLogo $size $size "$store/Grabpic-$size.png" }
Copy-Item "$store/Grabpic-256.png" "$assets/GrabPic-256.png" -Force
Copy-Item "$store/Grabpic-128.png" "$assets/GrabPic-128.png" -Force
Copy-Item "$store/Grabpic-512.png" "$root/docs/images/icon.png" -Force
# A true multi-resolution ICO with color PNG frames, rather than an HICON mask conversion.
$frames=@(16,20,24,32,40,48,64,96,128,256)
$stream=[IO.File]::Create("$assets/GrabPic.ico"); $writer=[IO.BinaryWriter]::new($stream)
$writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$frames.Count)
$offset=6+16*$frames.Count; $buffers=@()
foreach($size in $frames) {
 $bytes=[IO.File]::ReadAllBytes("$store/Grabpic-$size.png"); $buffers+=,@($bytes)
 $dimension=if($size -eq 256){0}else{$size}
 $writer.Write([byte]$dimension); $writer.Write([byte]$dimension); $writer.Write([byte]0); $writer.Write([byte]0)
 $writer.Write([uint16]1); $writer.Write([uint16]32); $writer.Write([uint32]$bytes.Length); $writer.Write([uint32]$offset); $offset+=$bytes.Length
}
foreach($bytes in $buffers) { $writer.Write([byte[]]$bytes) }; $writer.Dispose(); $stream.Dispose()
Copy-Item "$assets/GrabPic.ico" "$store/Grabpic.ico" -Force
foreach($definition in @(@('Square44x44Logo',44,44),@('Square150x150Logo',150,150),@('Square71x71Logo',71,71),@('Square310x310Logo',310,310),@('Wide310x150Logo',310,150),@('StoreLogo',50,50))) {
 foreach($scale in @(100,125,150,200,400)) { DrawLogo ([int]($definition[1]*$scale/100)) ([int]($definition[2]*$scale/100)) "$package/$($definition[0]).scale-$scale.png" }
 Copy-Item "$package/$($definition[0]).scale-100.png" "$package/$($definition[0]).png" -Force
}
foreach($size in @(16,20,24,30,32,36,40,44,48,60,64,72,80,96,128,256)) {
 DrawLogo $size $size "$package/Square44x44Logo.targetsize-$size.png"
 Copy-Item "$package/Square44x44Logo.targetsize-$size.png" "$package/Square44x44Logo.targetsize-${size}_altform-unplated.png" -Force
 Copy-Item "$package/Square44x44Logo.targetsize-$size.png" "$package/Square44x44Logo.targetsize-${size}_altform-lightunplated.png" -Force
}
Write-Output 'Generated color application icons, Store package assets, and submission PNGs.'
