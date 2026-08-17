Set-StrictMode -Version 2.0
function New-DefaultInstallerConfig {
 [pscustomobject]@{
  SchemaVersion=2; Emulator='rAthena'; RootPath='C:\Server'; RAthenaPath='C:\Server\rAthena'; PandasWSPath='C:\Server\PandasWS'; ClientPatchPath='C:\Server\WARP0716'; ROenglishREPath='C:\Server\ROenglishRE'; NpcBig5Path='C:\Server\rathena-npc-big5'; PacketVersion=20260107
  Repositories=[pscustomobject]@{RAthena=[pscustomobject]@{Url='https://github.com/rathena/rathena.git';Branch='master'};PandasWS=[pscustomobject]@{Url='https://github.com/PandasWS/Pandas.git';Branch='master'};ClientPatch=[pscustomobject]@{Url='https://github.com/CrazyBebop/WARP0716.git';Branch='main'};ROenglishRE=[pscustomobject]@{Url='https://github.com/llchrisll/ROenglishRE.git';Branch='master'};NpcBig5=[pscustomobject]@{Url='https://github.com/xvn5002036/rathena-npc-big5.git';Branch='main'}}
  Database=[pscustomobject]@{Engine='MariaDB';HostName='127.0.0.1';Port=3306;MainDatabase='rathenadb';LogDatabase='rathenalog';WebDatabase='rathenadb';UserName='root';Password='';ServerUserName='rathenadbusr';ServerPassword='froggopass';CharacterSet='utf8mb4';Collation='utf8mb4_unicode_520_ci'}
 }
}
function Save-InstallerConfig { param($Config); if(-not(Test-Path $script:ConfigPath)){New-Item -ItemType Directory -Path $script:ConfigPath -Force|Out-Null}; [IO.File]::WriteAllText($script:ConfigFile,($Config|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($true))); Write-Log ('設定已儲存：{0}' -f $script:ConfigFile) }
function Get-InstallerConfig {
 if(-not(Test-Path $script:ConfigFile)){ $d=New-DefaultInstallerConfig; Save-InstallerConfig $d; return $d }
 try { $s=[IO.File]::ReadAllText($script:ConfigFile,[Text.Encoding]::UTF8); if([string]::IsNullOrWhiteSpace($s)){throw '設定檔為空白'}; return ($s|ConvertFrom-Json) }
 catch { $b='{0}.broken-{1}' -f $script:ConfigFile,(Get-Date -Format yyyyMMdd-HHmmss); Copy-Item $script:ConfigFile $b -Force; $d=New-DefaultInstallerConfig; Save-InstallerConfig $d; return $d }
}
function Select-Emulator {
 Write-Host ''; Write-Host '[1] rAthena'; Write-Host '    使用 rAthena 官方核心與其 GitHub 原始碼。' -ForegroundColor DarkGray
 Write-Host '[2] PandasWS'; Write-Host '    使用 PandasWS 核心與其 GitHub 原始碼。' -ForegroundColor DarkGray
 $c=Read-Host ('選擇核心（目前 {0}）' -f $script:InstallerConfig.Emulator)
 if($c -eq '1'){$script:InstallerConfig.Emulator='rAthena'} elseif($c -eq '2'){$script:InstallerConfig.Emulator='PandasWS'}
 Save-InstallerConfig $script:InstallerConfig
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
 Write-Host ('核心：{0}' -f $core.Name); Write-Host ('安裝路徑：{0}' -f $core.Path); Write-Host ('MariaDB：{0}:{1}' -f $d.HostName,$d.Port); Write-Host ('主要資料庫：{0}' -f $d.MainDatabase); Write-Host ('紀錄資料庫：{0}' -f $d.LogDatabase); Write-Host ('管理帳號：{0}' -f $d.UserName); Write-Host ('管理密碼：{0}' -f $d.Password); Write-Host ('伺服器帳號：{0}' -f $d.ServerUserName); Write-Host ('伺服器密碼：{0}' -f $d.ServerPassword); Write-Host ('PACKETVER：{0}' -f $c.PacketVersion)
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
