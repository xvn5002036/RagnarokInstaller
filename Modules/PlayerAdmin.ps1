Set-StrictMode -Version 2.0

function Write-PlayerAdminSettings {
 param([Parameter(Mandatory=$true)][string]$Path)
 $database=$script:InstallerConfig.Database
 $core=Get-CoreInfo
 $settings=[ordered]@{
  Server=[string]$database.HostName
  Port=[string]$database.Port
  Database=[string]$database.MainDatabase
  User=[string]$database.ServerUserName
  Password=[string]$database.ServerPassword
  CorePath=[string]$core.Path
  CoreName=[string]$core.Name
  Url='http://127.0.0.1:5080'
 }
 [IO.File]::WriteAllText($Path,($settings|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
 Write-Log -Message ('已建立玩家管理後台設定：{0}' -f $Path) -FileName 'PlayerAdmin.log'
}

function Install-OrUpdatePlayerAdmin {
 $path=[string]$script:InstallerConfig.PlayerAdminPath
 $sourcePath=Join-Path $script:AppPath 'Tools\RathenaPlayerAdmin'
 $settingsPath=Join-Path $path 'local-settings.json'
 if(-not(Test-Path -LiteralPath (Join-Path $sourcePath 'RathenaPlayerAdmin.csproj') -PathType Leaf)){
  throw ('安裝器內建的 RathenaPlayerAdmin 原始碼不完整：{0}' -f $sourcePath)
 }
 Write-Host '[..] 正在從安裝器內建版本更新玩家管理後台...' -ForegroundColor Cyan
 Copy-DirectoryContent -Source $sourcePath -Destination $path -Exclude @('.git','bin','obj','artifacts','.dotnet','local-settings.json')
 # Always refresh this file from the installation manager. This keeps Player
 # Admin connected to the currently selected rAthena or PandasWS core.
 Write-PlayerAdminSettings -Path $settingsPath
 if(-not(Test-Path -LiteralPath (Join-Path $sourcePath 'Start.ps1') -PathType Leaf)){throw ('玩家管理後台缺少環境準備檔：{0}' -f (Join-Path $sourcePath 'Start.ps1'))}
 Write-Host '[..] 正在確認玩家管理後台的 .NET 8 執行環境...' -ForegroundColor Cyan
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $sourcePath 'Start.ps1') -SetupOnly
 if($LASTEXITCODE -ne 0){throw '玩家管理後台的 .NET 8 執行環境準備失敗。'}
 Write-Host ('[OK] 玩家管理後台位置：{0}' -f $path) -ForegroundColor Green
 Write-Host '[i] 後台版本由本安裝器管理；更新安裝器後按 [I] 即可套用新版。' -ForegroundColor Cyan
}

function Start-PlayerAdmin {
 $installedPath=[string]$script:InstallerConfig.PlayerAdminPath
 $path=Join-Path $script:AppPath 'Tools\RathenaPlayerAdmin'
 $startPath=Join-Path $path 'Start.ps1'
 $sourceSettings=Join-Path $path 'local-settings.json'
 $installedSettings=Join-Path $installedPath 'local-settings.json'
 $installedDotNet=Join-Path $installedPath '.dotnet\dotnet.exe'
 if(-not(Test-Path -LiteralPath $startPath -PathType Leaf)){throw '安裝器內建的玩家管理後台不完整，請重新下載安裝器專案。'}
 # J uses Tools\RathenaPlayerAdmin, so write current core settings here every
 # time instead of reusing settings from a previously selected core.
 Write-PlayerAdminSettings -Path $sourceSettings
 # J always opens the bundled source. Its private .NET runtime is kept in the
 # installed Player Admin folder, so pass that runtime to the child process.
 # This prevents J from downloading anything or closing immediately when the
 # system-wide .NET SDK is not installed.
 if(Test-Path -LiteralPath $installedDotNet -PathType Leaf){
  $dotNetRoot=Split-Path -Parent $installedDotNet
  $escapedRoot=$dotNetRoot.Replace("'","''")
  $escapedStart=$startPath.Replace("'","''")
  $arguments='-NoProfile -ExecutionPolicy Bypass -Command "& { $env:DOTNET_ROOT = '''+$escapedRoot+''' ; $env:PATH = '''+$escapedRoot+';'' + $env:PATH ; & '''+$escapedStart+''' }"'
 } else {
  $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$startPath+'"'
 }
 Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WorkingDirectory $path
 $script:MenuNotice='玩家管理後台已從 Tools\RathenaPlayerAdmin 啟動；準備完成後會開啟 http://127.0.0.1:5080。'
 Write-Host ('[OK] 已開啟：{0}' -f $startPath) -ForegroundColor Green
 Write-Host ('[i] 使用路徑：{0}' -f $path) -ForegroundColor Cyan
 Write-Host '[i] 後台只供本機使用；請勿將 5080 連接埠直接公開到網際網路。' -ForegroundColor Yellow
}
