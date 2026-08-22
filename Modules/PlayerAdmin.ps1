Set-StrictMode -Version 2.0

function Write-PlayerAdminSettings {
 param([Parameter(Mandatory=$true)][string]$Path)
 $database=$script:InstallerConfig.Database
 $settings=[ordered]@{
  Server=[string]$database.HostName
  Port=[string]$database.Port
  Database=[string]$database.MainDatabase
  User=[string]$database.ServerUserName
  Password=[string]$database.ServerPassword
  Url='http://127.0.0.1:5080'
 }
 [IO.File]::WriteAllText($Path,($settings|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
 Write-Log -Message ('已建立玩家管理後台設定：{0}' -f $Path) -FileName 'PlayerAdmin.log'
}

function Install-OrUpdatePlayerAdmin {
 $path=[string]$script:InstallerConfig.PlayerAdminPath
 $sourcePath=Join-Path $script:AppPath 'Tools\RathenaPlayerAdmin'
 $settingsPath=Join-Path $path 'local-settings.json'
 $savedSettings=$null
 if(Test-Path -LiteralPath $settingsPath -PathType Leaf){
  $savedSettings=[IO.File]::ReadAllText($settingsPath,[Text.Encoding]::UTF8)
 }

 if(-not(Test-Path -LiteralPath (Join-Path $sourcePath 'RathenaPlayerAdmin.csproj') -PathType Leaf)){
  throw ('安裝器內建的 RathenaPlayerAdmin 原始碼不完整：{0}' -f $sourcePath)
 }
 Write-Host '[..] 正在從安裝器內建版本更新玩家管理後台...' -ForegroundColor Cyan
 Copy-DirectoryContent -Source $sourcePath -Destination $path -Exclude @('.git','bin','obj','artifacts','.dotnet','local-settings.json')
 if($null -ne $savedSettings){
  [IO.File]::WriteAllText($settingsPath,$savedSettings,(New-Object Text.UTF8Encoding($false)))
 } else {Write-PlayerAdminSettings -Path $settingsPath}
 if(-not(Test-Path -LiteralPath (Join-Path $path 'Start.cmd') -PathType Leaf)){throw ('玩家管理後台缺少啟動檔：{0}' -f (Join-Path $path 'Start.cmd'))}
 $dotnet=Get-InstalledDotNet8Sdk
 if(-not$dotnet){throw '尚未安裝 .NET 8 SDK，請先執行 [1] 安裝 / 更新開發環境。'}
 Write-Host ('[OK] .NET 8 SDK：{0}（{1}）' -f $dotnet.Version,$dotnet.Path) -ForegroundColor Green
 Write-Host ('[OK] 玩家管理後台位置：{0}' -f $path) -ForegroundColor Green
 Write-Host '[i] 後台版本由本安裝器管理；更新安裝器後按 [I] 即可套用新版。' -ForegroundColor Cyan
}

function Start-PlayerAdmin {
 $installedPath=[string]$script:InstallerConfig.PlayerAdminPath
 $path=Join-Path $script:AppPath 'Tools\RathenaPlayerAdmin'
 $startPath=Join-Path $path 'Start.cmd'
 $sourceSettings=Join-Path $path 'local-settings.json'
 $installedSettings=Join-Path $installedPath 'local-settings.json'
 if(-not(Test-Path -LiteralPath $startPath -PathType Leaf)){throw '安裝器內建的玩家管理後台不完整，請重新下載安裝器專案。'}
 if(Test-Path -LiteralPath $installedSettings -PathType Leaf){
  Copy-Item -LiteralPath $installedSettings -Destination $sourceSettings -Force
 } elseif(-not(Test-Path -LiteralPath $sourceSettings -PathType Leaf)){
  Write-PlayerAdminSettings -Path $sourceSettings
 }
 if(-not(Get-InstalledDotNet8Sdk)){throw '尚未安裝 .NET 8 SDK，請先執行 [1] 安裝 / 更新開發環境。'}
 Start-Process -FilePath $startPath -WorkingDirectory $path
 $script:MenuNotice='玩家管理後台已從 Tools\RathenaPlayerAdmin 啟動；準備完成後會開啟 http://127.0.0.1:5080。'
 Write-Host ('[OK] 已開啟：{0}' -f $startPath) -ForegroundColor Green
 Write-Host ('[i] 使用路徑：{0}' -f $path) -ForegroundColor Cyan
 Write-Host '[i] 後台只供本機使用；請勿將 5080 連接埠直接公開到網際網路。' -ForegroundColor Yellow
}
