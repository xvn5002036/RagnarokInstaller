Set-StrictMode -Version 2.0
<# 設定管理：讀寫 installer.json，保存安裝路徑、核心、資料庫與 Player Admin 設定。 #>
function New-DefaultInstallerConfig {
 [pscustomobject]@{
  SchemaVersion=5; Emulator='rAthena'; CoreSelectionCompleted=$false; RootPath='C:\Server'; RAthenaPath='C:\Server\rAthena'; PandasWSPath='C:\Server\PandasWS'; ClientPatchPath='C:\Server\WARP0716'; ROenglishREPath='C:\Server\ROenglishRE'; NpcBig5Path='C:\Server\rathena-npc-big5'; PlayerAdminPath='C:\Server\RathenaPlayerAdmin'; PacketVersion=20260219
  Repositories=[pscustomobject]@{RAthena=[pscustomobject]@{Url='https://github.com/rathena/rathena.git';Branch='master'};PandasWS=[pscustomobject]@{Url='https://github.com/PandasWS/Pandas.git';Branch='master'};ClientPatch=[pscustomobject]@{Url='https://github.com/CrazyBebop/WARP0716.git';Branch='main'};ROenglishRE=[pscustomobject]@{Url='https://github.com/llchrisll/ROenglishRE.git';Branch='master'};NpcBig5=[pscustomobject]@{Url='https://github.com/xvn5002036/rathena-npc-big5.git';Branch='main'};PlayerAdmin=[pscustomobject]@{Url='https://github.com/xvn5002036/RathenaPlayerAdmin.git';Branch='main'}}
  Database=[pscustomobject]@{Engine='MariaDB';HostName='127.0.0.1';Port=3306;MainDatabase='rathenadb';LogDatabase='rathenalog';WebDatabase='rathenadb';UserName='root';Password='';ServerUserName='rathenadbusr';ServerPassword='froggopass';CharacterSet='utf8mb4';Collation='utf8mb4_unicode_520_ci'}
  WebApi=[pscustomobject]@{BindAddress='127.0.0.1';Port=8888;PublicUrl='http://127.0.0.1:8888'}
 }
}
function Save-InstallerConfig { param($Config); if(-not(Test-Path $script:ConfigPath)){New-Item -ItemType Directory -Path $script:ConfigPath -Force|Out-Null}; [IO.File]::WriteAllText($script:ConfigFile,($Config|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($true))); Write-Log ('設定已儲存：{0}' -f $script:ConfigFile) }
function Get-InstallerConfig {
 if(-not(Test-Path $script:ConfigFile)){ return (New-DefaultInstallerConfig) }
 try {
  $s=[IO.File]::ReadAllText($script:ConfigFile,[Text.Encoding]::UTF8);if([string]::IsNullOrWhiteSpace($s)){throw '設定檔為空白'}
  $c=$s|ConvertFrom-Json;$defaults=New-DefaultInstallerConfig
  if(-not($c.PSObject.Properties.Name -contains 'PlayerAdminPath')){$c|Add-Member -NotePropertyName PlayerAdminPath -NotePropertyValue $defaults.PlayerAdminPath}
  if(-not($c.Repositories.PSObject.Properties.Name -contains 'PlayerAdmin')){$c.Repositories|Add-Member -NotePropertyName PlayerAdmin -NotePropertyValue $defaults.Repositories.PlayerAdmin}
  if(-not($c.PSObject.Properties.Name -contains 'CoreSelectionCompleted')){$c|Add-Member -NotePropertyName CoreSelectionCompleted -NotePropertyValue $false}
  if(-not($c.PSObject.Properties.Name -contains 'WebApi')){$c|Add-Member -NotePropertyName WebApi -NotePropertyValue $defaults.WebApi}
  if([int]$c.PacketVersion -eq 20260107){$c.PacketVersion=20260219}
  if([int]$c.SchemaVersion -lt 5){$c.SchemaVersion=5;Save-InstallerConfig $c}
  return $c
 }
 catch { $b='{0}.broken-{1}' -f $script:ConfigFile,(Get-Date -Format yyyyMMdd-HHmmss); Copy-Item $script:ConfigFile $b -Force; return (New-DefaultInstallerConfig) }
}
function Complete-CoreSelection {
 param([ValidateSet('rAthena','PandasWS')][string]$Emulator)
 $script:InstallerConfig.Emulator=$Emulator
 $script:InstallerConfig.CoreSelectionCompleted=$true
 Save-InstallerConfig $script:InstallerConfig
 $core=Get-CoreInfo
 $script:MenuNotice=('目前核心已設定為 {0}，工作路徑：{1}' -f $core.Name,$core.Path)
 Write-Host ('[OK] {0}' -f $script:MenuNotice) -ForegroundColor Green
}
function Initialize-FirstRunCoreSelection {
 if($script:InstallerConfig.CoreSelectionCompleted -eq $true){return}
 Write-Host ''
 Write-Host '========================================================' -ForegroundColor Cyan
 Write-Host '首次使用：請選擇要安裝與管理的伺服器核心' -ForegroundColor Cyan
 Write-Host '[1] rAthena' -ForegroundColor White
 Write-Host ('    工作路徑：{0}' -f $script:InstallerConfig.RAthenaPath) -ForegroundColor DarkGray
 Write-Host '[2] PandasWS' -ForegroundColor White
 Write-Host ('    工作路徑：{0}' -f $script:InstallerConfig.PandasWSPath) -ForegroundColor DarkGray
 Write-Host '選擇會儲存為預設核心；往後重開不會再詢問，只有按 [S] 才能切換。' -ForegroundColor Yellow
 while($true){
  $choice=(Read-Host '請輸入 1 或 2').Trim()
  if($choice -eq '1'){Complete-CoreSelection 'rAthena';return}
  if($choice -eq '2'){Complete-CoreSelection 'PandasWS';return}
  Write-Host '[X] 請輸入 1（rAthena）或 2（PandasWS）。' -ForegroundColor Red
 }
}
function Select-Emulator {
 Write-Host ''; Write-Host '[1] rAthena'; Write-Host ('    切換後會在 {0} 工作。' -f $script:InstallerConfig.RAthenaPath) -ForegroundColor DarkGray
 Write-Host '[2] PandasWS'; Write-Host ('    切換後會在 {0} 工作。' -f $script:InstallerConfig.PandasWSPath) -ForegroundColor DarkGray
 $c=Read-Host ('選擇核心（目前 {0}）' -f $script:InstallerConfig.Emulator)
 if($c -eq '1'){Complete-CoreSelection 'rAthena'} elseif($c -eq '2'){Complete-CoreSelection 'PandasWS'} else {Write-Host '[-] 未切換核心。' -ForegroundColor DarkYellow;return}
}
function Get-CoreInfo {
 if($script:InstallerConfig.Emulator -eq 'PandasWS'){return [pscustomobject]@{Name='PandasWS';Path=$script:InstallerConfig.PandasWSPath;Repo=$script:InstallerConfig.Repositories.PandasWS}}
 return [pscustomobject]@{Name='rAthena';Path=$script:InstallerConfig.RAthenaPath;Repo=$script:InstallerConfig.Repositories.RAthena}
}
function Edit-DatabaseConnection {
 $d=$script:InstallerConfig.Database
 $d.HostName=Read-WithDefault '主機' ([string]$d.HostName); $d.Port=[int](Read-WithDefault '連接埠' ([string]$d.Port)); $d.MainDatabase=Read-WithDefault '主要資料庫' $d.MainDatabase; $d.LogDatabase=Read-WithDefault '紀錄資料庫' $d.LogDatabase; $d.WebDatabase=Read-WithDefault '網站資料庫' $d.WebDatabase; $d.UserName=Read-WithDefault '管理使用者' $d.UserName
 $pw=Read-Host '新密碼（直接 Enter 保留）'; if(-not [string]::IsNullOrEmpty($pw)){$d.Password=$pw}
 Save-InstallerConfig $script:InstallerConfig; Write-Host '[OK] 安裝程式資料庫設定已儲存。' -ForegroundColor Green
}
function Show-InstallerConfig {
 $c=$script:InstallerConfig; $d=$c.Database; $core=Get-CoreInfo
 Write-Host ''; Write-Host '目前設定' -ForegroundColor Cyan
 Write-Host ('核心：{0}' -f $core.Name); Write-Host ('安裝路徑：{0}' -f $core.Path);Write-Host ('玩家管理後台：{0}' -f $c.PlayerAdminPath); Write-Host ('MariaDB：{0}:{1}' -f $d.HostName,$d.Port); Write-Host ('主要資料庫：{0}' -f $d.MainDatabase); Write-Host ('紀錄資料庫：{0}' -f $d.LogDatabase); Write-Host ('管理帳號：{0}' -f $d.UserName); Write-Host ('管理密碼：{0}' -f $d.Password); Write-Host ('伺服器帳號：{0}' -f $d.ServerUserName); Write-Host ('伺服器密碼：{0}' -f $d.ServerPassword); Write-Host ('PACKETVER：{0}' -f $c.PacketVersion);Write-Host ('遊戲 Web API：{0}' -f $c.WebApi.PublicUrl)
 $svc=Get-MariaDbService
 if($svc){Write-Host ('MariaDB 服務：{0} / {1}' -f $svc.Name,$svc.State);Write-Host ('啟動類型：{0}' -f $svc.StartMode)}
 else{Write-Host 'MariaDB 服務：未偵測到'}
 $python=Get-InstalledPythonVersion;if($python){Write-Host ('Python：{0}' -f $python.Version);Write-Host ('Python 路徑：{0}' -f $python.Path)}else{Write-Host 'Python：未安裝'}
 Write-Host ''; Write-Host '伺服器執行檔（核心根目錄）' -ForegroundColor Cyan
 foreach($exeName in @('login-server.exe','char-server.exe','map-server.exe','web-server.exe')){
  $exePath=Join-Path $core.Path $exeName
  if(Test-Path -LiteralPath $exePath){Write-Host ('[OK] {0}' -f $exeName) -ForegroundColor Green}else{Write-Host ('[ ]  {0}' -f $exeName) -ForegroundColor DarkYellow}
 }
}
