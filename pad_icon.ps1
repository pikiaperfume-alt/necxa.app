Add-Type -AssemblyName System.Drawing
$basePath = "C:\Users\KNEST\.gemini\antigravity\scratch\necxa_flutter\assets\images"
$img = [System.Drawing.Image]::FromFile("$basePath\app_icon.png")
$w = $img.Width
$h = $img.Height
# If 35% space is left, logo takes 65% of the total size.
$newSize = [Math]::Ceiling([Math]::Max($w, $h) / 0.65)
$newImg = New-Object System.Drawing.Bitmap([int]$newSize, [int]$newSize)
$g = [System.Drawing.Graphics]::FromImage($newImg)
$g.Clear([System.Drawing.Color]::Transparent)
$x = ($newSize - $w) / 2
$y = ($newSize - $h) / 2
$g.DrawImage($img, [int]$x, [int]$y, $w, $h)
$newImg.Save("$basePath\app_icon_padded.png", [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose()
$newImg.Dispose()
$img.Dispose()
Write-Host "Image padded successfully."
