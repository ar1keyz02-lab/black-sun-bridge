<#
  AR1KEYZ Media Bridge — помощник для обоев AR1KEYZ (Wallpaper Engine).

  Обои не могут сами управлять плеером, поэтому этот скрипт слушает http://127.0.0.1:47811/
  (доступен только с этого ПК) и:
    • передаёт пауза / следующий / предыдущий / перемотка в Windows — работает с любым плеером
      из системной панели громкости (Яндекс Музыка, Spotify, браузер...);
    • меняет громкость самого плеера (как в микшере громкости Windows), не трогая общую громкость;
    • отдаёт обоям текст песни из Яндекс Музыки (с таймингами, если есть);
    • ставит и снимает лайк в Яндекс Музыке через её неофициальный API. Трек ищется по названию
      и исполнителю. Нужен OAuth-токен; он хранится зашифрованным (DPAPI, расшифровать может
      только текущий пользователь Windows) в %APPDATA%\AR1KEYZ\bridge.json.

  Команды:
    powershell -ExecutionPolicy Bypass -File media-bridge.ps1              запуск
    powershell -ExecutionPolicy Bypass -File media-bridge.ps1 -SetToken    сохранить токен Яндекс Музыки
    powershell -ExecutionPolicy Bypass -File media-bridge.ps1 -Install     автозапуск со входом в Windows + запуск сейчас
    powershell -ExecutionPolicy Bypass -File media-bridge.ps1 -Uninstall   убрать автозапуск
#>
param([switch]$SetToken,[switch]$Install,[switch]$Uninstall,[int]$Port=47811)
$ErrorActionPreference='Stop'

$cfgDir=Join-Path $env:APPDATA 'AR1KEYZ'
$cfgFile=Join-Path $cfgDir 'bridge.json'
$lnk=Join-Path ([Environment]::GetFolderPath('Startup')) 'AR1KEYZ Media Bridge.lnk'

# ---------- служебные режимы ----------
if($SetToken){
  Write-Host 'Токен Яндекс Музыки: откройте в браузере ссылку ниже, войдите в аккаунт и скопируйте'
  Write-Host 'из адресной строки значение access_token=... (до символа &).'
  Write-Host 'https://oauth.yandex.ru/authorize?response_type=token&client_id=23cabbbdc6cd418abb4b39c32c41195d'
  $sec=Read-Host 'Вставьте токен' -AsSecureString
  New-Item -ItemType Directory -Force $cfgDir | Out-Null
  @{token=($sec | ConvertFrom-SecureString)} | ConvertTo-Json | Set-Content $cfgFile -Encoding UTF8
  Write-Host "Сохранено в $cfgFile. Перезапустите помощник, если он уже работает."
  return
}
if($Install){
  $sh=New-Object -ComObject WScript.Shell
  $s=$sh.CreateShortcut($lnk)
  $s.TargetPath="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
  $s.Arguments="-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  $s.WorkingDirectory=$PSScriptRoot
  $s.Save()
  Start-Process $s.TargetPath $s.Arguments -WindowStyle Hidden
  Write-Host "Автозапуск добавлен ($lnk), помощник запущен."
  return
}
if($Uninstall){
  if(Test-Path $lnk){Remove-Item $lnk}
  Write-Host 'Автозапуск убран. Работающий помощник можно закрыть в диспетчере задач (powershell.exe).'
  return
}

# ---------- системные медиаконтролы Windows (SMTC) ----------
Add-Type -AssemblyName System.Runtime.WindowsRuntime,System.Web
$null=[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager,Windows.Media.Control,ContentType=WindowsRuntime]
$asTask=[System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
function Await($op,[type]$t){$task=$asTask.MakeGenericMethod($t).Invoke($null,@($op));[void]$task.Wait(5000);$task.Result}

$MGR=[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]
$PROPS=[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties]
$mgr=Await ($MGR::RequestAsync()) $MGR

# текущий сеанс Windows; если его нет — сеанс Яндекс Музыки
function Get-Session{
  $s=$mgr.GetCurrentSession()
  if(-not $s){$s=@($mgr.GetSessions()) | Where-Object {$_.SourceAppUserModelId -match 'yandex'} | Select-Object -First 1}
  $s
}

# ---------- громкость приложения (как в микшере громкости Windows) ----------
Add-Type -TypeDefinition (Get-Content (Join-Path $PSScriptRoot 'app-volume.cs') -Raw -Encoding UTF8)
# процесс плеера ищем по словам из его ID в медиаконтролах: ru.yandex.desktop.music -> yandex, music
function Get-PlayerPid($aumid){
  $words=@($aumid -split '[^A-Za-z0-9]+' | Where-Object {$_.Length -ge 4 -and $_ -notin 'desktop','microsoft','windows','exe'})
  foreach($id in [AR1KEYZ.AppVolume]::Pids()){
    $p=Get-Process -Id $id -ErrorAction SilentlyContinue
    if(-not $p){continue}
    $hay="$($p.ProcessName) $($p.Path)"
    foreach($w in $words){if($hay -match [regex]::Escape($w)){return $id}}
  }
  $null
}

# ---------- Яндекс Музыка (неофициальный API) ----------
$YaApi='https://api.music.yandex.net' # имена переменных в PowerShell не различают регистр — не путать с $ya ниже
$token=$null
if(Test-Path $cfgFile){
  try{
    $sec=(Get-Content $cfgFile -Raw | ConvertFrom-Json).token | ConvertTo-SecureString
    $token=[Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
  }catch{Write-Warning "Не удалось прочитать токен: $($_.Exception.Message)"}
}
$ya=@{uid=$null;likes=$null;likesAt=[datetime]::MinValue;found=@{};lyrics=@{};error=$null}

function Ya($method,$path,$body){
  $p=@{Uri=$YaApi+$path;Method=$method;UseBasicParsing=$true;TimeoutSec=10
       Headers=@{Authorization="OAuth $token";'X-Yandex-Music-Client'='YandexMusicAndroid/24023621'}}
  if($body){$p.Body=$body;$p.ContentType='application/x-www-form-urlencoded'}
  $r=Invoke-WebRequest @p
  [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray()) | ConvertFrom-Json
}
# список лайков держим в памяти и обновляем раз в 5 минут (лайк могли поставить и в самом приложении)
function Ya-Likes([switch]$Force){
  if(-not $ya.uid){$ya.uid=(Ya GET '/account/status').result.account.uid}
  if($Force -or -not $ya.likes -or ((Get-Date)-$ya.likesAt).TotalMinutes -ge 5){
    $set=New-Object 'System.Collections.Generic.HashSet[string]'
    foreach($t in (Ya GET "/users/$($ya.uid)/likes/tracks").result.library.tracks){[void]$set.Add([string]$t.id)}
    $ya.likes=$set;$ya.likesAt=Get-Date
  }
}
# трек по названию и исполнителю: точное совпадение названия и исполнителя, иначе названия, иначе первый
function Ya-Find($title,$artist){
  $key="$artist`n$title"
  if($ya.found.ContainsKey($key)){return $ya.found[$key]}
  $res=(Ya GET ('/search?type=track&page=0&nocorrect=false&text='+[uri]::EscapeDataString("$artist $title"))).result.tracks.results
  $best=$res | Where-Object {$_.title -ieq $title -and (@($_.artists.name) -join ', ') -match [regex]::Escape(($artist -split ',')[0].Trim())} | Select-Object -First 1
  if(-not $best){$best=$res | Where-Object {$_.title -ieq $title} | Select-Object -First 1}
  if(-not $best){$best=$res | Select-Object -First 1}
  $hit=if($best){@{id=[string]$best.id;album=[string]$best.albums[0].id}}else{$null}
  $ya.found[$key]=$hit
  $hit
}

# текст песни из Яндекс Музыки: сначала с таймингами (LRC), иначе обычный.
# Запрос подписывается HMAC-SHA256 ключом из приложения Яндекс Музыки (так делают неофициальные клиенты).
function Ya-Lyrics($title,$artist){
  $t=Ya-Find $title $artist
  if(-not $t){return @{ok=$false;error='track not found'}}
  if($ya.lyrics.ContainsKey($t.id)){return $ya.lyrics[$t.id]}
  $out=@{ok=$false;error='no lyrics'}
  foreach($fmt in 'LRC','TEXT'){
    try{
      $ts=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
      $mac=New-Object Security.Cryptography.HMACSHA256 (,[Text.Encoding]::UTF8.GetBytes('p93jhgh689SBReK6ghtw62'))
      $sign=[Convert]::ToBase64String($mac.ComputeHash([Text.Encoding]::UTF8.GetBytes("$($t.id)$ts")))
      $url=(Ya GET "/tracks/$($t.id)/lyrics?format=$fmt&timeStamp=$ts&sign=$([uri]::EscapeDataString($sign))").result.downloadUrl
      $txt=[Text.Encoding]::UTF8.GetString((Invoke-WebRequest -UseBasicParsing $url -TimeoutSec 10).RawContentStream.ToArray())
      if($txt.Trim()){$out=@{ok=$true;synced=($fmt -eq 'LRC');text=$txt};break}
    }catch{}
  }
  $ya.lyrics[$t.id]=$out
  $out
}

# ---------- команды ----------
function Get-Status{
  $o=@{ok=$true;yandex=[bool]$token;yandexError=$ya.error;session=$null}
  $s=Get-Session
  if(-not $s){return $o}
  $m=Await ($s.TryGetMediaPropertiesAsync()) $PROPS
  $pb=$s.GetPlaybackInfo();$tl=$s.GetTimelineProperties()
  $o.session=@{app=$s.SourceAppUserModelId;title=$m.Title;artist=$m.Artist
    playing=($pb.PlaybackStatus -eq 'Playing');canSeek=$pb.Controls.IsPlaybackPositionEnabled
    canNext=$pb.Controls.IsNextEnabled;canPrev=$pb.Controls.IsPreviousEnabled
    duration=($tl.EndTime-$tl.StartTime).TotalSeconds;liked=$null;volume=$null}
  $vp=Get-PlayerPid $s.SourceAppUserModelId
  if($vp){$o.session.volume=[Math]::Round([AR1KEYZ.AppVolume]::Get($vp),3)}
  if($token -and $m.Title){
    try{Ya-Likes;$t=Ya-Find $m.Title $m.Artist;if($t){$o.session.liked=$ya.likes.Contains($t.id)};$ya.error=$null}
    catch{$ya.error=$_.Exception.Message}
    $o.yandexError=$ya.error
  }
  $o
}
function Invoke-Command2($path,$q){
  $s=Get-Session
  if(-not $s){return @{ok=$false;error='no media session'}}
  switch($path){
    '/toggle'{$r=Await ($s.TryTogglePlayPauseAsync()) ([bool])}
    '/next'  {$r=Await ($s.TrySkipNextAsync()) ([bool])}
    '/prev'  {$r=Await ($s.TrySkipPreviousAsync()) ([bool])}
    '/seek'  {$r=Await ($s.TryChangePlaybackPositionAsync([long]([double]$q['pos']*1e7))) ([bool])}
    '/volume'{
      $vp=Get-PlayerPid $s.SourceAppUserModelId
      if(-not $vp){return @{ok=$false;error='player audio session not found'}}
      $r=[AR1KEYZ.AppVolume]::Set($vp,[float]::Parse($q['v'],[Globalization.CultureInfo]::InvariantCulture)) -gt 0
    }
    '/like'  {
      if(-not $token){return @{ok=$false;error='no yandex token'}}
      $m=Await ($s.TryGetMediaPropertiesAsync()) $PROPS
      Ya-Likes;$t=Ya-Find $m.Title $m.Artist
      if(-not $t){return @{ok=$false;error='track not found in yandex music'}}
      if($ya.likes.Contains($t.id)){Ya POST "/users/$($ya.uid)/likes/tracks/remove" "track-ids=$($t.id)" | Out-Null;[void]$ya.likes.Remove($t.id);$liked=$false}
      else{Ya POST "/users/$($ya.uid)/likes/tracks/add-multiple" "track-ids=$($t.id):$($t.album)" | Out-Null;[void]$ya.likes.Add($t.id);$liked=$true}
      return @{ok=$true;liked=$liked}
    }
    default{return @{ok=$false;error='unknown command'}}
  }
  @{ok=[bool]$r}
}

# ---------- HTTP ----------
$http=New-Object Net.HttpListener
$http.Prefixes.Add("http://127.0.0.1:$Port/")
try{$http.Start()}catch{Write-Host "Порт $Port занят — помощник, вероятно, уже запущен.";return}
Write-Host "AR1KEYZ Media Bridge: http://127.0.0.1:$Port/  (Яндекс-токен: $(if($token){'есть'}else{'нет'}))"

while($http.IsListening){
  $ctx=$http.GetContext();$req=$ctx.Request;$res=$ctx.Response
  $res.AddHeader('Access-Control-Allow-Origin','*')
  $res.AddHeader('Access-Control-Allow-Private-Network','true')
  if($req.HttpMethod -eq 'OPTIONS'){$res.AddHeader('Access-Control-Allow-Methods','GET');$res.StatusCode=204;$res.Close();continue}
  try{
    $path=$req.Url.AbsolutePath
    # QueryString у HttpListener декодирует не в UTF-8 (портит кириллицу и японский) — разбираем сами
    $q=[System.Web.HttpUtility]::ParseQueryString($req.Url.Query,[Text.Encoding]::UTF8)
    if($path -eq '/diag'){
      # обои присылают диагностику (?d=...), без параметра — отдаём последнюю присланную
      if($q['d']){$lastDiag=$q['d'];$out=@{ok=$true}}
      else{$out=if($lastDiag){$lastDiag | ConvertFrom-Json}else{@{ok=$false;error='no diagnostics from wallpaper yet'}}}
    }
    elseif($path -eq '/status'){$out=Get-Status}
    elseif($path -eq '/lyrics'){
      $out=if($token){Ya-Lyrics $q['title'] $q['artist']}else{@{ok=$false;error='no yandex token'}}
    }
    else{$out=Invoke-Command2 $path $q}
  }catch{$out=@{ok=$false;error=$_.Exception.Message}}
  $bytes=[Text.Encoding]::UTF8.GetBytes(($out | ConvertTo-Json -Depth 5 -Compress))
  $res.ContentType='application/json; charset=utf-8'
  $res.OutputStream.Write($bytes,0,$bytes.Length);$res.Close()
}
