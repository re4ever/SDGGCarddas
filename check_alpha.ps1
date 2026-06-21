Add-Type -AssemblyName System.Drawing
$dir = 'E:\E-Drive\내개인자료\SD건담외전_스캔\2_카드다스업스케일\1_SD건담외전\1_지크지온편\1_라크로아의용자'
$files = Get-ChildItem -Path $dir -Filter '*.png'
foreach ($f in $files) {
    $img = [System.Drawing.Image]::FromFile($f.FullName)
    $bmp = new-object System.Drawing.Bitmap($img)
    $isPrism = $false
    for ($y=0; $y -lt 50; $y+=10) {
        for ($x=0; $x -lt 50; $x+=10) {
            if ($bmp.GetPixel($x, $y).A -lt 255) {
                $isPrism = $true
                break
            }
        }
        if ($isPrism) { break }
    }
    if ($isPrism) { Write-Output "$($f.Name) has transparency" }
    $bmp.Dispose()
    $img.Dispose()
}
