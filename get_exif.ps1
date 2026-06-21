Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile('E:\E-Drive\내개인자료\SD건담외전_스캔\2_카드다스업스케일\1_SD건담외전\1_지크지온편\1_라크로아의용자\11100010.png')
foreach ($prop in $img.PropertyItems) {
    $val = [System.Text.Encoding]::ASCII.GetString($prop.Value)
    Write-Output "$($prop.Id): $val"
}
$img.Dispose()
