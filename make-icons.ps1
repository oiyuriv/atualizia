# Gera os ícones PNG do Atualiz.IA (preto, brilho verde, "A" serifado com ponto verde), irmão do ícone do Yur.IA.
Add-Type -AssemblyName System.Drawing
$out = Join-Path $PSScriptRoot 'icons'
New-Item -ItemType Directory -Force $out | Out-Null

function New-Icon([int]$s, [string]$path) {
  $bmp = New-Object System.Drawing.Bitmap $s, $s
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.Clear([System.Drawing.Color]::FromArgb(255, 5, 6, 5))

  # brilho verde embaixo à esquerda
  $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
  $gp.AddEllipse([single](-0.5 * $s), [single](0.28 * $s), [single](1.3 * $s), [single](1.3 * $s))
  $br = New-Object System.Drawing.Drawing2D.PathGradientBrush $gp
  $br.CenterColor = [System.Drawing.Color]::FromArgb(190, 31, 174, 94)
  $br.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
  $g.FillPath($br, $gp)

  # reflexo claro em cima à direita
  $gp2 = New-Object System.Drawing.Drawing2D.GraphicsPath
  $gp2.AddEllipse([single](0.35 * $s), [single](-0.45 * $s), [single](0.95 * $s), [single](0.85 * $s))
  $br2 = New-Object System.Drawing.Drawing2D.PathGradientBrush $gp2
  $br2.CenterColor = [System.Drawing.Color]::FromArgb(55, 200, 255, 220)
  $br2.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
  $g.FillPath($br2, $gp2)

  # "A" serifado
  $fam = New-Object System.Drawing.FontFamily 'Georgia'
  $txt = New-Object System.Drawing.Drawing2D.GraphicsPath
  $fmt = [System.Drawing.StringFormat]::GenericTypographic
  $txt.AddString('A', $fam, [int][System.Drawing.FontStyle]::Regular, [single](0.66 * $s), (New-Object System.Drawing.PointF 0, 0), $fmt)
  $b = $txt.GetBounds()
  $dot = 0.12 * $s
  $gap = 0.03 * $s
  $groupW = $b.Width + $gap + $dot
  $x0 = ($s - $groupW) / 2
  $y0 = ($s - $b.Height) / 2
  $m = New-Object System.Drawing.Drawing2D.Matrix
  $m.Translate([single]($x0 - $b.X), [single]($y0 - $b.Y))
  $txt.Transform($m)
  $white = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.PointF 0, $y0), (New-Object System.Drawing.PointF 0, ($y0 + $b.Height)), ([System.Drawing.Color]::FromArgb(255, 250, 255, 252)), ([System.Drawing.Color]::FromArgb(255, 170, 200, 182))
  $g.FillPath($white, $txt)

  # ponto verde
  $dx = $x0 + $b.Width + $gap
  $dy = $y0 + $b.Height - $dot
  $green = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.PointF 0, $dy), (New-Object System.Drawing.PointF 0, ($dy + $dot)), ([System.Drawing.Color]::FromArgb(255, 169, 255, 208)), ([System.Drawing.Color]::FromArgb(255, 61, 242, 140))
  $g.FillEllipse($green, [single]$dx, [single]$dy, [single]$dot, [single]$dot)

  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
}

New-Icon 180 (Join-Path $out 'icon-180.png')
New-Icon 192 (Join-Path $out 'icon-192.png')
New-Icon 512 (Join-Path $out 'icon-512.png')
Write-Host 'Ícones gerados em' $out
