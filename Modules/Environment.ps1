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

function Get-InstalledMariaDbVersion {
 param([string]$ClientPath)
 if([string]::IsNullOrWhiteSpace($ClientPath) -or -not(Test-Path -LiteralPath $ClientPath)){return $null}
 $oldPreference=$ErrorActionPreference;$ErrorActionPreference='Continue'
 try{$output=(& $ClientPath --version 2>&1|Out-String).Trim();$exitCode=$LASTEXITCODE}finally{$ErrorActionPreference=$oldPreference}
 if($exitCode -eq 0 -and $output -match '(?i)(MariaDB|Distrib)'){return $output}
 return $null
}

function Get-NativeToolVersion {
 param([string]$CommandName,[string[]]$Arguments=@('--version'))
 $command=Get-Command $CommandName -ErrorAction SilentlyContinue
 if(-not$command){return $null}
 $oldPreference=$ErrorActionPreference;$ErrorActionPreference='Continue'
 try{$output=(& $command.Source @Arguments 2>&1|Out-String).Trim();$exitCode=$LASTEXITCODE}finally{$ErrorActionPreference=$oldPreference}
 if($exitCode -eq 0 -and -not[string]::IsNullOrWhiteSpace($output)){return $output.Split([Environment]::NewLine)[0].Trim()}
 return $null
}

function Get-DevelopmentEnvironmentState {
 $states=@()
 $gitVersion=Get-NativeToolVersion 'git.exe' @('--version')
 $states+=[pscustomobject]@{Name='Git';Package='git';Version=$gitVersion;Installed=![string]::IsNullOrWhiteSpace($gitVersion)}
 $ninjaVersion=Get-NativeToolVersion 'ninja.exe' @('--version')
 $states+=[pscustomobject]@{Name='Ninja';Package='ninja';Version=$ninjaVersion;Installed=![string]::IsNullOrWhiteSpace($ninjaVersion)}
 $sevenZipCommand=Get-Command '7z.exe' -ErrorAction SilentlyContinue
 $candidate=Join-Path $env:ProgramFiles '7-Zip\7z.exe'
 $sevenZipPath=if(Test-Path -LiteralPath $candidate){$candidate}elseif($sevenZipCommand){$sevenZipCommand.Source}else{$null}
 $sevenZipVersion=if($sevenZipPath){(Get-Item -LiteralPath $sevenZipPath).VersionInfo.ProductVersion}else{$null}
 $states+=[pscustomobject]@{Name='7-Zip';Package='7zip';Version=$sevenZipVersion;Installed=![string]::IsNullOrWhiteSpace($sevenZipVersion)}
 $python=Get-InstalledPythonVersion
 $states+=[pscustomobject]@{Name='Python';Package='python';Version=$(if($python){$python.Version}else{$null});Installed=($null-ne$python)}
 $vcRuntime=Join-Path $env:WINDIR 'System32\MSVCR110.dll'
 $vcVersion=if(Test-Path -LiteralPath $vcRuntime){(Get-Item -LiteralPath $vcRuntime).VersionInfo.FileVersion}else{$null}
 $states+=[pscustomobject]@{Name='Visual C++ 2012 x64 Runtime';Package='vcredist2012';Version=$vcVersion;Installed=![string]::IsNullOrWhiteSpace($vcVersion)}
 return $states
}

function Get-ChocolateyPackageVersion {
 param([Parameter(Mandatory=$true)][string]$PackageName)
 if(-not(Test-Command choco)){return $null}
 $escaped=[regex]::Escape($PackageName)
 $line=& choco list --local-only --exact $PackageName --limit-output 2>$null | Where-Object{$_ -match ('^{0}\|' -f $escaped)} | Select-Object -First 1
 if($line){return ($line -split '\|')[1]}
 return $null
}

function Get-ChocolateyMariaDbPackage {
 return Get-ChocolateyPackageVersion 'mariadb.install'
}

function Install-PythonOfficialUnattended {
 $pythonVersion='3.14.6'
 $downloadUrl='https://www.python.org/ftp/python/3.14.6/python-3.14.6-amd64.exe'
 $expectedHash='14b3e9a710a3fcf0bd9b55ab6b60412bd91227563f813fc49040cabc0209e0bd'
 $expectedBytes=30774112L
 $downloadDirectory=Join-Path $env:TEMP 'RagnarokInstaller'
 $installerPath=Join-Path $downloadDirectory ('python-{0}-amd64.exe' -f $pythonVersion)
 if(-not(Test-Path -LiteralPath $downloadDirectory)){New-Item -ItemType Directory -Path $downloadDirectory -Force|Out-Null}

 if(Test-Path -LiteralPath $installerPath){
  $existingHash=(Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
  if($existingHash -ne $expectedHash){Remove-Item -LiteralPath $installerPath -Force}
 }
 if(-not(Test-Path -LiteralPath $installerPath)){
  Write-Host ('[..] Chocolatey 無法取得 Python，改由 Python 官方下載 {0}...' -f $pythonVersion) -ForegroundColor Yellow
  $webClient=New-Object System.Net.WebClient
  $task=$webClient.DownloadFileTaskAsync([Uri]$downloadUrl,$installerPath)
  while(-not$task.IsCompleted){
   $length=if(Test-Path -LiteralPath $installerPath){(Get-Item -LiteralPath $installerPath).Length}else{0L}
   $percent=[Math]::Min(99,[int](100*$length/$expectedBytes))
   $completed=[Math]::Min(30,[int](30*$percent/100));$bar=('#'*$completed)+('-'*(30-$completed))
   Write-Host ("`r[{0}] 下載 Python：{1}% ({2:N1}/{3:N1} MB)      " -f $bar,$percent,($length/1MB),($expectedBytes/1MB)) -NoNewline -ForegroundColor Cyan
   Start-Sleep -Milliseconds 500
  }
  try{$task.GetAwaiter().GetResult()}finally{$webClient.Dispose()}
  Write-Host ''
 }
 $actualHash=(Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
 if($actualHash -ne $expectedHash){throw 'Python 官方安裝程式 SHA-256 驗證失敗，已停止安裝。'}

 Write-Host '[..] 正在執行 Python 官方無人值守安裝...' -ForegroundColor Cyan
 $arguments='/quiet InstallAllUsers=1 PrependPath=1 Include_test=0 Include_launcher=1 InstallLauncherAllUsers=1'
 $process=Start-Process -FilePath $installerPath -ArgumentList $arguments -PassThru
 [void]$process.Handle;$started=Get-Date;$frame=0;$width=24
 while(-not$process.HasExited){
  $position=$frame%($width-4);$bar=(' '*$position)+'====>'+(' '*($width-$position-5))
  Write-Host ("`r[{0}] 安裝 Python，PID {1}，耗時 {2:hh\:mm\:ss}      " -f $bar,$process.Id,((Get-Date)-$started)) -NoNewline -ForegroundColor Cyan
  $frame++;Start-Sleep -Milliseconds 500;$process.Refresh()
 }
 Write-Host '';$process.WaitForExit();$process.Refresh()
 if($process.ExitCode -notin @(0,3010)){throw ('Python 官方安裝失敗（錯誤碼 {0}）。' -f $process.ExitCode)}
 $env:Path=[Environment]::GetEnvironmentVariable('Path','Machine')+';'+[Environment]::GetEnvironmentVariable('Path','User')
 $python=Get-InstalledPythonVersion
 if(-not$python){throw 'Python 官方安裝已結束，但仍無法讀取版本。' }
 return $python
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
 Write-Host '========================================================' -ForegroundColor Cyan
 Write-Host ' 開發環境版本偵測' -ForegroundColor Cyan
 Write-Host '========================================================' -ForegroundColor Cyan
 $states=@(Get-DevelopmentEnvironmentState)
 foreach($state in $states){if($state.Installed){Write-Host ('[OK] {0}：{1}' -f $state.Name,$state.Version) -ForegroundColor Green}else{Write-Host ('[ ]  {0}：無法讀取版本，將下載安裝' -f $state.Name) -ForegroundColor Yellow}}
 $missingStates=@($states|Where-Object{-not$_.Installed})
 $installedStates=@($states|Where-Object{$_.Installed})
 foreach($state in $missingStates){
  if($state.Package -eq 'python'){
   Write-Host '[..] 嘗試由 Chocolatey 無人值守安裝 Python...' -ForegroundColor Cyan
   Invoke-Native choco @('install','python','-y','--no-progress') '' 'Install.log' -AllowFailure|Out-Null
   $env:Path=[Environment]::GetEnvironmentVariable('Path','Machine')+';'+[Environment]::GetEnvironmentVariable('Path','User')
   if(-not(Get-InstalledPythonVersion)){Install-PythonOfficialUnattended|Out-Null}
   continue
  }
  $recordedVersion=Get-ChocolateyPackageVersion $state.Package
  if($recordedVersion){
   Write-Host ('[..] {0} 有 Chocolatey 紀錄 {1}，但版本無法執行；正在強制修復...' -f $state.Name,$recordedVersion) -ForegroundColor Yellow
   Invoke-Native choco @('upgrade',$state.Package,'--force','-y','--no-progress') '' 'Install.log'|Out-Null
  }else{
   Write-Host ('[..] 無人值守下載安裝：{0}' -f $state.Name) -ForegroundColor Cyan
   Invoke-Native choco @('install',$state.Package,'-y','--no-progress') '' 'Install.log'|Out-Null
  }
 }
 $regularInstalled=@($installedStates|Where-Object{$_.Package-ne'python'}|ForEach-Object{$_.Package})
 if($regularInstalled.Count -gt 0){
  Write-Host ('[..] 檢查並更新：{0}' -f ($regularInstalled -join '、')) -ForegroundColor Cyan
  Invoke-Native choco (@('upgrade')+$regularInstalled+@('-y','--no-progress')) '' 'Install.log'|Out-Null
 }
 if($installedStates.Package -contains 'python'){
  Write-Host '[..] 檢查 Python 更新（來源暫時無法使用時保留目前可用版本）...' -ForegroundColor Cyan
  Invoke-Native choco @('upgrade','python','-y','--no-progress') '' 'Install.log' -AllowFailure|Out-Null
 }
  $env:Path=[Environment]::GetEnvironmentVariable('Path','Machine')+';'+[Environment]::GetEnvironmentVariable('Path','User')
 $finalStates=@(Get-DevelopmentEnvironmentState)
 $failed=@($finalStates|Where-Object{-not$_.Installed})
 if($failed.Count -gt 0){throw ('下列工具安裝或修復後仍無法讀取版本：{0}。請查看 Install.log。' -f (($failed|ForEach-Object{$_.Name})-join '、'))}
 $python=Get-InstalledPythonVersion
 Write-Host ('[OK] Python：{0}' -f $python.Version) -ForegroundColor Green
 Write-Host ('     路徑：{0}' -f $python.Path) -ForegroundColor DarkGray
 try{$vs=Find-VisualStudioCppEnvironment;$vsVersion=(Get-Item -LiteralPath $vs.MSBuild).VersionInfo.FileVersion;Write-Host ('[OK] Visual Studio C++ Build Tools：{0}' -f $vsVersion) -ForegroundColor Green;$vsOperation='upgrade'}catch{Write-Host '[ ]  Visual Studio C++ Build Tools：無法讀取版本，將下載安裝' -ForegroundColor Yellow;$vsOperation='install'}
 $vsArgs=@('-NoExit','-ExecutionPolicy','Bypass','-Command',"choco $vsOperation visualstudio2022buildtools visualstudio2022-workload-vctools -y --package-parameters='--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.26100 --add Microsoft.VisualStudio.Component.VC.TestAdapterForBoostTest --add Microsoft.VisualStudio.Component.VC.ASAN --add Microsoft.VisualStudio.Component.VC.vcpkg' 2>&1 | Tee-Object -FilePath '$($script:LogsPath)\VSBuildTools.log' -Append")
 Start-Process powershell.exe -Verb RunAs -ArgumentList $vsArgs
 Write-Host '[OK] 基本工具、Python 與 Visual C++ 2012 Runtime 已完成；Visual Studio Build Tools 已在獨立視窗啟動。' -ForegroundColor Green
}

function Install-MariaDBEnvironment {
 Ensure-Chocolatey
 $serviceBefore=Get-MariaDbService
 $clientBefore=Find-InstalledMariaDbClient
 $installedVersion=Get-InstalledMariaDbVersion $clientBefore
 $packageVersion=Get-ChocolateyMariaDbPackage

 Write-Host '========================================================' -ForegroundColor Cyan
 Write-Host ' MariaDB 安裝 / 更新' -ForegroundColor Cyan
 Write-Host ' 安裝引擎：v6.0.3 / 清除舊 data + mariadb.install + MSI 修復' -ForegroundColor DarkGray
 Write-Host '========================================================' -ForegroundColor Cyan
 if($serviceBefore -and $clientBefore -and $installedVersion){
  Write-Host ('[OK] MariaDB 版本：{0}' -f $installedVersion) -ForegroundColor Green
  Write-Host ('[OK] Windows 服務：{0} / {1}' -f $serviceBefore.Name,$serviceBefore.State) -ForegroundColor Green
  Write-Host ('[..] 正在檢查並更新到 Chocolatey 最新可用版本（目前 {0}）...' -f $(if($packageVersion){$packageVersion}else{'未知'}))
  $arguments=@('upgrade','mariadb.install','-y')
  $actionName='更新 MariaDB MSI'
 } elseif($packageVersion -or $serviceBefore -or $clientBefore){
  Write-Host '[X] MariaDB 無法完整讀取版本、用戶端或 Windows 服務，判定為損壞安裝。' -ForegroundColor Red
  if($packageVersion){Write-Host ('    Chocolatey 紀錄版本：{0}' -f $packageVersion) -ForegroundColor DarkGray}
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
}
