# kanji_ocr.ps1 - Windows OCR(ja) kanji-box extractor
# Reads job config from kocr_job.txt (same folder). No command-line args (avoids quoting issues).
# kocr_job.txt keys (one per line):  DIR=  OUT=  REGION=dlg|desc|name|full  PER=6  SCALE=5  OCRW=1720  IDS=a,b,c  (or IDFILE=path)
# Purpose: crop only kanji (CJK) glyph boxes at xN for verification; OUT+ocr.txt = OCR text for auto-diff vs stored jd.
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Runtime.WindowsRuntime

$cfgPath=Join-Path $PSScriptRoot 'kocr_job.txt'
if(-not(Test-Path $cfgPath)){ Write-Output "ERR: no kocr_job.txt"; exit 1 }
$cfg=@{}
foreach($ln in ([System.IO.File]::ReadAllLines($cfgPath,(New-Object System.Text.UTF8Encoding($false))))){ if($ln -match '^\s*([A-Za-z]+)\s*=\s*(.*)$'){ $cfg[$matches[1].ToUpper()]=$matches[2].Trim() } }
$Dir=$cfg['DIR']; $Out=$cfg['OUT']; $Region=$cfg['REGION']; if(-not $Region){$Region='dlg'}
$Per=[int]($cfg['PER']); if($Per -le 0){$Per=6}
$Scale=[int]($cfg['SCALE']); if($Scale -le 0){$Scale=5}
$OcrW=[int]($cfg['OCRW']); if($OcrW -le 0){$OcrW=1720}
$idsrc=$cfg['IDS']
if($cfg['IDFILE'] -and (Test-Path $cfg['IDFILE'])){ $idsrc=(Get-Content $cfg['IDFILE'] -Raw) }
$ids=@($idsrc -split '[,\s]+' | Where-Object { $_ -ne '' })
Write-Output ("Dir=$Dir`nOut=$Out`nRegion=$Region Per=$Per Scale=$Scale OcrW=$OcrW  ids=$($ids.Count)")

# WinRT await helper
$asTaskGeneric=([System.WindowsRuntimeSystemExtensions].GetMethods()|?{$_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'})[0]
function Await($op,$t){ $m=$asTaskGeneric.MakeGenericMethod($t); $task=$m.Invoke($null,@($op)); $task.Wait(); $task.Result }
[Windows.Globalization.Language,Windows.Foundation,ContentType=WindowsRuntime]|Out-Null
[Windows.Storage.StorageFile,Windows.Foundation,ContentType=WindowsRuntime]|Out-Null
[Windows.Graphics.Imaging.BitmapDecoder,Windows.Foundation,ContentType=WindowsRuntime]|Out-Null
[Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime]|Out-Null
$engine=[Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage((New-Object Windows.Globalization.Language 'ja'))
if(-not $engine){ Write-Output "ERR: ja OCR engine"; exit 1 }

function RegionRect($w,$h,$region){
  $asp=$w/$h
  if($region -eq 'dlg'){ if($asp -gt 1.2){$ry=0.0;$rh=0.155}else{$ry=0.012;$rh=0.10}; $rx=0.02;$rw=0.83 }
  elseif($region -eq 'desc'){ if($asp -gt 1.2){$ry=0.797;$rh=0.207}else{$ry=0.835;$rh=0.144}; $rx=0.28;$rw=0.45 }
  elseif($region -eq 'name'){ if($asp -gt 1.2){$ry=0.795;$rh=0.21}else{$ry=0.833;$rh=0.15}; $rx=0.0;$rw=0.46 }
  else { $ry=0;$rh=1;$rx=0;$rw=1 }
  return @([int]($w*$rx),[int]($h*$ry),[int]($w*$rw),[int]($h*$rh))
}

$tmp="$env:TEMP\kocr_band.png"
$ocrLines=New-Object System.Collections.ArrayList
$grp=0
$rows=New-Object System.Collections.ArrayList
function FlushRows($grp,$rows,$Out,$Scale){
  if($rows.Count -eq 0){return}
  $gap=24;$lblW=160;$canvasW=3200
  $rowHs=@(); foreach($r in $rows){ $mh=0; foreach($b in $r.Boxes){ $dh=[int]([double]$b.Height+16)*$Scale; if($dh -gt $mh){$mh=$dh} }; if($mh -lt 60){$mh=60}; $rowHs+=$mh+24 }
  [int]$ch=0; foreach($x in $rowHs){$ch+=$x}
  $cv=New-Object System.Drawing.Bitmap $canvasW,$ch; $g=[System.Drawing.Graphics]::FromImage($cv); $g.Clear([System.Drawing.Color]::Black); $g.InterpolationMode='HighQualityBicubic'
  $f=New-Object System.Drawing.Font('Consolas',22,[System.Drawing.FontStyle]::Bold)
  [int]$y=0
  for($i=0;$i -lt $rows.Count;$i++){ $r=$rows[$i]
    $g.FillRectangle([System.Drawing.Brushes]::Yellow,0,$y,$lblW,38); $g.DrawString($r.Id,$f,[System.Drawing.Brushes]::Black,4,$y+6)
    [int]$x=$lblW+$gap
    foreach($b in $r.Boxes){
      [int]$sx=[Math]::Max(0,[int]([double]$b.X)-8);[int]$sy=[Math]::Max(0,[int]([double]$b.Y)-8);[int]$sw=[int]([double]$b.Width)+16;[int]$sh=[int]([double]$b.Height)+16
      if($sx+$sw -gt $r.Img.Width){$sw=$r.Img.Width-$sx}; if($sy+$sh -gt $r.Img.Height){$sh=$r.Img.Height-$sy}
      [int]$dw=$sw*$Scale;[int]$dh=$sh*$Scale
      if($x+$dw -gt $canvasW){break}
      $g.DrawImage($r.Img,(New-Object System.Drawing.Rectangle $x,($y+4),$dw,$dh),(New-Object System.Drawing.Rectangle $sx,$sy,$sw,$sh),'Pixel')
      $x+=$dw+$gap
    }
    $y+=$rowHs[$i]
  }
  $g.Dispose(); $cv.Save("$Out$grp.png"); $cv.Dispose()
  foreach($r in $rows){ $r.Img.Dispose() }
}

$cnt=0
foreach($id in $ids){
  $p="$Dir\$id.png"; if(-not(Test-Path $p)){ Write-Output "MISS $id"; continue }
  $img=[System.Drawing.Image]::FromFile($p); $w=$img.Width; $h=$img.Height
  $rr=RegionRect $w $h $Region
  $oh=[int]($rr[3]*($OcrW/$rr[2]))
  $band=New-Object System.Drawing.Bitmap $OcrW,$oh; $bg=[System.Drawing.Graphics]::FromImage($band); $bg.InterpolationMode='HighQualityBicubic'
  $bg.DrawImage($img,(New-Object System.Drawing.Rectangle 0,0,$OcrW,$oh),(New-Object System.Drawing.Rectangle $rr[0],$rr[1],$rr[2],$rr[3]),'Pixel'); $bg.Dispose(); $img.Dispose()
  $band.Save($tmp)
  $file=Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($tmp)) ([Windows.Storage.StorageFile])
  $stream=Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
  $decoder=Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $sb=Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  $res=Await ($engine.RecognizeAsync($sb)) ([Windows.Media.Ocr.OcrResult])
  $stream.Dispose()
  [void]$ocrLines.Add("$id|"+($res.Text -replace '\s+',''))
  $boxes=New-Object System.Collections.ArrayList
  foreach($line in $res.Lines){ foreach($word in $line.Words){
    $hasK=$false; foreach($c in $word.Text.ToCharArray()){ $cc=[int]$c; if($cc -ge 0x3400 -and $cc -le 0x9FFF){ $hasK=$true; break } }
    if($hasK){ [void]$boxes.Add($word.BoundingRect) } } }
  Write-Output ("  $id kanji=$($boxes.Count)")
  [void]$rows.Add(@{Id=$id;Img=$band;Boxes=$boxes})
  $cnt++
  if($cnt%$Per -eq 0){ FlushRows $grp $rows $Out $Scale; $grp++; $rows.Clear() }
}
if($rows.Count -gt 0){ FlushRows $grp $rows $Out $Scale; $grp++ }
[System.IO.File]::WriteAllLines("${Out}ocr.txt",$ocrLines,(New-Object System.Text.UTF8Encoding($false)))
Write-Output ("DONE composites=$grp ocr=${Out}ocr.txt")
