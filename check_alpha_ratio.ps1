Add-Type -AssemblyName System.Drawing
$dir = 'E:\E-Drive\내개인자료\SD건담외전_스캔\2_카드다스업스케일\1_SD건담외전\1_지크지온편\1_라크로아의용자'
$files = Get-ChildItem -Path $dir -Filter '*.png' | Select-Object -First 20
foreach ($f in $files) {
    $img = [System.Drawing.Image]::FromFile($f.FullName)
    $bmp = new-object System.Drawing.Bitmap($img)
    $transparentCount = 0
    $total = $bmp.Width * $bmp.Height
    # Sample a grid of pixels to be fast
    for ($y=0; $y -lt $bmp.Height; $y+=5) {
        for ($x=0; $x -lt $bmp.Width; $x+=5) {
            if ($bmp.GetPixel($x, $y).A -lt 255) {
                $transparentCount++
            }
        }
    }
    $ratio = $transparentCount / (($bmp.Width/5) * ($bmp.Height/5))
    if ($ratio -gt 0.05) {
        Write-Output "$($f.Name) has high transparency ratio: $ratio"
    }
    $bmp.Dispose()
    $img.Dispose()
}
