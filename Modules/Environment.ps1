Set-StrictMode -Version 2.0

function Ensure-Chocolatey {
 if(Test-Command choco){return}
 Write-Host '[..] 安裝 Chocolatey...'
 $old=[Net.ServicePointManager]::SecurityProtocol;[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
 try{iex((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))}finally{[Net.ServicePointManager]::SecurityProtocol=$old}
 $env:Path=[Environment]::GetEnvironmentVariable('Path','Machine')+';'+[Environment]::GetEnvironmentVariable('Path','User')
 if(-not(Test-Command choco)){throw 'Chocolatey 安裝失敗。'}
}

function Find-InstalledMariaDbClient {
 foreach($name in @('mariadb.exe','mysql.exe')){$command=Get-Command $name -ErrorAction SilentlyContinue;if($command){return $command.Source}}
 $found=Get-ChildItem 'C:\Program Files\MariaDB*\bin\mariadb.exe','C:\Program Files\MariaDB*\bin\mysql.exe' -File -ErrorAction SilentlyContinue|Sort-Object FullName -Descending|Select-Object -First 1
 if($found){return $found.FullName}
 return $null
}

function Get-ChocolateyMariaDbPackage {
 if(-not(Test-Command choco)){return $null}
 $line=&choco list --local-only --exact mariadb.install --limit-output 2>$null|Where-Object{$_ -match '^mariadb\.install\|'}|Select-Object -First 1
 if($line){return ($line-split '\|')[1]}
 return $null
}

function Invoke-ChocolateyMariaDbMonitored {
 param([string[]]$Arguments,[string]$ActionName)
 $choco=(Get-Command choco.exe -ErrorAction SilentlyContinue)
 if(-not$choco){throw '找不到 Chocolatey。'}
 $quoted=@($Arguments|ForEach-Object{if($_ -match '[\s"]'){'"'+($_ -replace '"','\"')+'"'}else{$_}})
 Write-Log -Message ('執行：choco {0}' -f ($quoted -join ' ')) -FileName 'MariaDB-Install.log'
 $process=Start-Process -FilePath $choco.Source -ArgumentList ($quoted -join ' ') -NoNewWindow -PassThru
 [void]$process.Handle;$started=Get-Date;$frame=0
 $width=24
 while(-not$process.HasExited){
  $position=$frame%($width-4)
  $bar=(' ' * $position)+'====>'+(' ' * ($width-$position-5))
  Write-Host ("`r[{0}] {1}，PID {2}，耗時 {3:hh\:mm\:ss}      " -f $bar,$ActionName,$process.Id,((Get-Date)-$started)) -NoNewline -ForegroundColor Cyan
  $frame++;Start-Sleep -Milliseconds 500;$process.Refresh()
 }
 Write-Host '';$process.WaitForExit();$process.Refresh()
 return [int]$process.ExitCode
}

function Move-BrokenMariaDbDataToBackup {
 param([string]$RootPath)
 $dataFolders=@(Get-ChildItem 'C:\Program Files\MariaDB*\data' -Directory -ErrorAction SilentlyContinue|Sort-Object FullName -Descending)
 if($dataFolders.Count -eq 0){return $null}

 $backupRoot=Join-Path $RootPath 'Backups'
 if(-not(Test-Path -LiteralPath $backupRoot)){New-Item -ItemType Directory -Path $backupRoot -Force|Out-Null}
 $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
 $lastBackup=$null
 foreach($dataFolder in $dataFolders){
  $versionFolder=Split-Path -Leaf (Split-Path -Parent $dataFolder.FullName)
  $safeVersion=$versionFolder -replace '[^A-Za-z0-9._-]','-'
  $backupPath=Join-Path $backupRoot ('MariaDB-data-before-clean-install-{0}-{1}' -f $safeVersion,$stamp)
  Write-Host ('[..] 將舊資料庫 data 移至安全備份：{0}' -f $backupPath) -ForegroundColor Yellow
  Write-Log -Message ('移動損壞安裝的 data：{0} -> {1}' -f $dataFolder.FullName,$backupPath) -FileName 'MariaDB-Install.log'
  Move-Item -LiteralPath $dataFolder.FullName -Destination $backupPath -Force
  $lastBackup=$backupPath

  $installFolder=Split-Path -Parent $dataFolder.FullName
  if((Test-Path -LiteralPath $installFolder)-and -not(Get-ChildItem -LiteralPath $installFolder -Force -ErrorAction SilentlyContinue|Select-Object -First 1)){
   Remove-Item -LiteralPath $installFolder -Force
  }
 }
 return $lastBackup
}

function Invoke-MariaDbMsiMonitored {
 param([string]$MsiPath)
 if(-not(Test-Path -LiteralPath $MsiPath)){throw ('找不到 MariaDB MSI：{0}' -f $MsiPath)}
 $msiLog=Join-Path $script:LogsPath 'MariaDB-MSI.log'
 $arguments='/i "{0}" SERVICENAME=MySQL /qn /norestart /l*v "{1}"' -f $MsiPath,$msiLog
 Write-Log -Message ('執行：msiexec.exe {0}' -f $arguments) -FileName 'MariaDB-Install.log'
 $process=Start-Process -FilePath 'msiexec.exe' -ArgumentList $arguments -NoNewWindow -PassThru
 [void]$process.Handle;$started=Get-Date;$frame=0;$width=24
 while(-not$process.HasExited){
  $position=$frame%($width-4);$bar=(' ' * $position)+'====>'+(' ' * ($width-$position-5))
  Write-Host ("`r[{0}] MariaDB MSI 修復安裝，PID {1}，耗時 {2:hh\:mm\:ss}      " -f $bar,$process.Id,((Get-Date)-$started)) -NoNewline -ForegroundColor Cyan
  $frame++;Start-Sleep -Milliseconds 500;$process.Refresh()
 }
 Write-Host '';$process.WaitForExit();$process.Refresh()
 if($process.ExitCode -notin @(0,3010)){throw ('MariaDB MSI 安裝失敗（錯誤碼 {0}）。請查看 MariaDB-MSI.log。' -f $process.ExitCode)}
}

function Wait-MariaDbService {
 param([int]$TimeoutSeconds=90)
 $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
 $started=Get-Date
 do{
  $service=Get-MariaDbService
  if($service){return $service}
  $elapsed=[int]((Get-Date)-$started).TotalSeconds
  $completed=[Math]::Min(30,[int](30*$elapsed/$TimeoutSeconds))
  $bar=('#' * $completed)+('-' * (30-$completed))
  Write-Host ("`r[{0}] 等待 MariaDB 建立 Windows 服務：{1}/{2} 秒      " -f $bar,$elapsed,$TimeoutSeconds) -NoNewline -ForegroundColor Cyan
  Start-Sleep -Seconds 2
 }while((Get-Date)-lt$deadline)
 Write-Host ''
 return $null
}

function Install-DevelopmentEnvironment {
 Ensure-Chocolatey
 Invoke-Native choco @('upgrade','git','cmake','ninja','7zip','vcredist2012','-y','--no-progress') '' 'Install.log'|Out-Null
 $vsArgs=@('-NoExit','-ExecutionPolicy','Bypass','-Command',"choco upgrade visualstudio2022buildtools visualstudio2022-workload-vctools -y --package-parameters='--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.26100 --add Microsoft.VisualStudio.Component.VC.CMake.Project --add Microsoft.VisualStudio.Component.VC.TestAdapterForBoostTest --add Microsoft.VisualStudio.Component.VC.ASAN --add Microsoft.VisualStudio.Component.VC.vcpkg' 2>&1 | Tee-Object -FilePath '$($script:LogsPath)\VSBuildTools.log' -Append")
 Start-Process powershell.exe -Verb RunAs -ArgumentList $vsArgs
 Write-Host '[OK] 基本工具與 Visual C++ 2012 Runtime 已完成；Visual Studio Build Tools 已在獨立視窗啟動。' -ForegroundColor Green
 Pause-Console
}

function Install-MariaDBEnvironment {
 Ensure-Chocolatey
 $serviceBefore=Get-MariaDbService
 $clientBefore=Find-InstalledMariaDbClient
 $packageVersion=Get-ChocolateyMariaDbPackage

 Write-Host '========================================================' -ForegroundColor Cyan
 Write-Host ' MariaDB 安裝 / 更新' -ForegroundColor Cyan
 Write-Host ' 安裝引擎：v6.0.3 / 清除舊 data + mariadb.install + MSI 修復' -ForegroundColor DarkGray
 Write-Host '========================================================' -ForegroundColor Cyan
 if($serviceBefore -and $clientBefore){
  Write-Host ('[OK] 已安裝，服務：{0} / {1}' -f $serviceBefore.Name,$serviceBefore.State) -ForegroundColor Green
  Write-Host ('[..] 正在檢查並更新到 Chocolatey 最新可用版本（目前 {0}）...' -f $(if($packageVersion){$packageVersion}else{'未知'}))
  $arguments=@('upgrade','mariadb.install','-y')
  $actionName='更新 MariaDB MSI'
 } elseif($packageVersion){
  Write-Host ('[X] 偵測到損壞安裝：Chocolatey 記錄為 {0}，但程式檔或 Windows 服務不存在。' -f $packageVersion) -ForegroundColor Red
  $backupPath=Move-BrokenMariaDbDataToBackup -RootPath $script:InstallerConfig.RootPath
  if($backupPath){Write-Host '[OK] 舊 data 已與新安裝斷開；新 MSI 將建立乾淨資料目錄。' -ForegroundColor Green}
  Write-Host '[..] 正在執行強制修復安裝...'
  $arguments=@('upgrade','mariadb.install','--force','-y')
  $actionName='修復 MariaDB MSI'
 } else{
  Write-Host '[ ] MariaDB：未安裝'
  $backupPath=Move-BrokenMariaDbDataToBackup -RootPath $script:InstallerConfig.RootPath
  if($backupPath){Write-Host '[OK] 已移開先前卸載遺留的 data，避免 MSI 1603。' -ForegroundColor Green}
  Write-Host '[..] 正在安裝 Chocolatey 最新可用版本...'
  $arguments=@('install','mariadb.install','-y')
  $actionName='安裝 MariaDB MSI'
 }

 $chocoExitCode=Invoke-ChocolateyMariaDbMonitored $arguments $actionName
 $env:Path=[Environment]::GetEnvironmentVariable('Path','Machine')+';'+[Environment]::GetEnvironmentVariable('Path','User')
 if($chocoExitCode -eq 0){
  $service=Wait-MariaDbService -TimeoutSeconds 15
  $client=Find-InstalledMariaDbClient
 }else{
  $service=$null
  $client=$null
  Write-Host ('[!] Chocolatey 回傳錯誤碼 {0}，自動切換至原始 MSI 覆蓋安裝。' -f $chocoExitCode) -ForegroundColor Yellow
  Write-Log -Message ('Chocolatey MariaDB 作業錯誤碼：{0}，切換原始 MSI。' -f $chocoExitCode) -FileName 'MariaDB-Install.log' -Level WARN
 }
 if((-not$service)-or(-not$client)){
  Write-Host ''
  Write-Host '[!] Chocolatey 套件完成，但實際程式或服務仍缺失，改用原始 MSI 修復。' -ForegroundColor Yellow
  $msi=Get-ChildItem 'C:\ProgramData\chocolatey\lib\mariadb.install\tools\mariadb-*-winx64.msi' -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 1
  if(-not$msi){throw '找不到 mariadb.install 套件內的 MSI，無法進行第二階段修復。'}
  Invoke-MariaDbMsiMonitored $msi.FullName
  $env:Path=[Environment]::GetEnvironmentVariable('Path','Machine')+';'+[Environment]::GetEnvironmentVariable('Path','User')
  $service=Wait-MariaDbService -TimeoutSeconds 90
  $client=Find-InstalledMariaDbClient
 }
 if(-not$service){throw 'MariaDB MSI 已結束，但沒有建立 Windows 服務。請查看 MariaDB-MSI.log。'}
 if(-not$client){throw 'MariaDB MSI 已結束，但找不到 mariadb.exe/mysql.exe。請查看 MariaDB-MSI.log。'}
 if($service.State -ne 'Running'){
  Write-Host ('[..] 啟動 MariaDB 服務：{0}' -f $service.Name)
  Start-Service -Name $service.Name
  $nativeService=Get-Service -Name $service.Name
  $nativeService.WaitForStatus('Running',[TimeSpan]::FromSeconds(60))
  $service=Get-MariaDbService
 }
 $versionOutput=&$client --version 2>$null
 Write-Host '[OK] MariaDB 安裝 / 更新完成。' -ForegroundColor Green
 Write-Host ('版本：{0}' -f $versionOutput)
 Write-Host ('服務：{0}' -f $service.Name)
 Write-Host ('狀態：{0}' -f $service.State)
 Write-Host ('用戶端：{0}' -f $client)
 Pause-Console
}
