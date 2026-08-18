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
 $repository=$script:InstallerConfig.Repositories.PlayerAdmin
 $settingsPath=Join-Path $path 'local-settings.json'
 $hadRepository=Test-Path -LiteralPath (Join-Path $path '.git')
 $savedSettings=$null
 if($hadRepository -and (Test-Path -LiteralPath $settingsPath -PathType Leaf)){
  $savedSettings=[IO.File]::ReadAllText($settingsPath,[Text.Encoding]::UTF8)
 }

 try{
  $null=Update-GitRepository 'RathenaPlayerAdmin' $repository.Url $repository.Branch $path
 }
 finally{
  if($null -ne $savedSettings -and (Test-Path -LiteralPath $path)){
   [IO.File]::WriteAllText($settingsPath,$savedSettings,(New-Object Text.UTF8Encoding($false)))
  }
 }

 if(-not$hadRepository){Write-PlayerAdminSettings -Path $settingsPath}
 if(-not(Test-Path -LiteralPath (Join-Path $path 'Start.cmd') -PathType Leaf)){throw ('玩家管理後台缺少啟動檔：{0}' -f (Join-Path $path 'Start.cmd'))}
 $dotnet=Get-InstalledDotNet8Sdk
 if(-not$dotnet){throw '尚未安裝 .NET 8 SDK，請先執行 [1] 安裝 / 更新開發環境。'}
 Write-Host ('[OK] .NET 8 SDK：{0}（{1}）' -f $dotnet.Version,$dotnet.Path) -ForegroundColor Green
 Write-Host ('[OK] 玩家管理後台位置：{0}' -f $path) -ForegroundColor Green
 Write-Host '[i] 此專案獨立安裝，不會修改 rAthena 或 PandasWS 核心檔案。' -ForegroundColor Cyan
}

function Start-PlayerAdmin {
 $path=[string]$script:InstallerConfig.PlayerAdminPath
 $startPath=Join-Path $path 'Start.cmd'
 if(-not(Test-Path -LiteralPath $startPath -PathType Leaf)){throw '尚未安裝玩家管理後台，請先執行 [I]。'}
 if(-not(Get-InstalledDotNet8Sdk)){throw '尚未安裝 .NET 8 SDK，請先執行 [1] 安裝 / 更新開發環境。'}
 Start-Process -FilePath $startPath -WorkingDirectory $path
 $script:MenuNotice='玩家管理後台已啟動；準備完成後會開啟 http://127.0.0.1:5080。'
 Write-Host ('[OK] 已開啟：{0}' -f $startPath) -ForegroundColor Green
 Write-Host '[i] 後台只供本機使用；請勿將 5080 連接埠直接公開到網際網路。' -ForegroundColor Yellow
}
