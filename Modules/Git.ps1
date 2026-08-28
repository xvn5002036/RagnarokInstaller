Set-StrictMode -Version 2.0

function ConvertTo-GitBashArgument {
 param([Parameter(Mandatory=$true)][string]$Value)
 # The installer repository URLs and destination paths are configuration values;
 # double quotes keep the normal Windows paths together for Git Bash.
 return '"'+$Value.Replace('"','\"')+'"'
}

function Get-GitBashPath {
 $git=Get-Command git.exe -ErrorAction SilentlyContinue
 if(-not$git){return $null}
 $gitRoot=Split-Path (Split-Path $git.Source -Parent) -Parent
 # git-bash.exe is only a launcher and returns before the clone has finished.
 # Run bash.exe itself so the installer can wait for the real Git exit code.
 $bashPath=Join-Path $gitRoot 'bin\bash.exe'
 if(Test-Path -LiteralPath $bashPath -PathType Leaf){return $bashPath}
 return $null
}

function Invoke-VisibleGitCommand {
 param([Parameter(Mandatory=$true)][string[]]$Arguments,[Parameter(Mandatory=$true)][string]$Name)
 $gitBash=Get-GitBashPath
 if(-not$gitBash){return $false}
 $command='exec git '+(($Arguments|ForEach-Object{ConvertTo-GitBashArgument ([string]$_)}) -join ' ')
 Write-Host ('[..] 正在以 Git Bash 視窗處理 {0}；視窗會顯示即時 Git 訊息。' -f $Name) -ForegroundColor Cyan
 $bashArguments='-lc "'+($command -replace '"','\"')+'"'
 $process=Start-Process -FilePath $gitBash -ArgumentList $bashArguments -PassThru
 $process.WaitForExit()
 if($process.ExitCode -ne 0){throw ('Git 處理失敗（錯誤碼 {0}）：{1}' -f $process.ExitCode,$Name)}
 return $true
}

function Invoke-GitMonitored {
 param([string[]]$Arguments,[string]$Name,[string]$Destination='')
 $git=Get-Command git.exe -ErrorAction SilentlyContinue
 if(-not$git){throw '找不到 Git，請先執行 [1]。'}
 Initialize-LogDirectory $script:LogsPath
 $captureId=[guid]::NewGuid().ToString('N')
 $stdoutPath=Join-Path $script:LogsPath ('.git-{0}.out' -f $captureId)
 $stderrPath=Join-Path $script:LogsPath ('.git-{0}.err' -f $captureId)
 $quoted=@($Arguments|ForEach-Object{if($_ -match '[\s"]'){'"'+($_ -replace '"','\"')+'"'}else{$_}})
 Write-Log -Message ('執行：git {0}' -f ($quoted -join ' ')) -FileName 'Git.log'
 # Show every Git operation in Git Bash: clone, fetch, checkout, and reset.
 # This applies equally to rAthena, WARP, ROenglishRE, and NPC 中文化.
 if(Invoke-VisibleGitCommand -Arguments $Arguments -Name $Name){
  Write-Log -Message ('Git Bash 已完成：{0}' -f $Name) -FileName 'Git.log'
  return
 }
 $env:GIT_PROGRESS_DELAY='0'
 $process=Start-Process -FilePath $git.Source -ArgumentList ($quoted -join ' ') -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
 [void]$process.Handle
 $started=Get-Date;$lastStatus=Get-Date
 while(-not$process.HasExited){
  if(((Get-Date)-$lastStatus).TotalSeconds -ge 2){
   $sizeText=''
   if($Destination -and (Test-Path -LiteralPath $Destination)){
    $packPath=Join-Path $Destination '.git\objects\pack'
    if(Test-Path -LiteralPath $packPath){
     # Measure-Object has no Sum property when Git has not created a pack file
     # yet. Keep monitoring instead of terminating the active clone process.
     $packFiles=@(Get-ChildItem -LiteralPath $packPath -File -ErrorAction SilentlyContinue)
     $bytes=0
     if($packFiles.Count -gt 0){$bytes=[long](($packFiles|Measure-Object Length -Sum).Sum)}
     if($bytes){$sizeText=('，已接收約 {0:N1} MB' -f ($bytes/1MB))}
    }
   }
   Write-Host ("`r[..] {0} 執行中，PID {1}，耗時 {2:hh\:mm\:ss}{3}      " -f $Name,$process.Id,((Get-Date)-$started),$sizeText) -NoNewline -ForegroundColor Cyan
   $lastStatus=Get-Date
  }
  Start-Sleep -Milliseconds 250;$process.Refresh()
 }
 Write-Host ''
 $process.WaitForExit();$process.Refresh()
 $capturedOutput=@()
 foreach($capturePath in @($stdoutPath,$stderrPath)){
  if(Test-Path -LiteralPath $capturePath){$capturedOutput+=@(Get-Content -LiteralPath $capturePath -ErrorAction SilentlyContinue)}
 }
 if($capturedOutput.Count -gt 0){Add-Content -LiteralPath (Join-Path $script:LogsPath 'Git.log') -Value $capturedOutput -Encoding UTF8}
 foreach($capturePath in @($stdoutPath,$stderrPath)){if(Test-Path -LiteralPath $capturePath){Remove-Item -LiteralPath $capturePath -Force -ErrorAction SilentlyContinue}}
 if($process.ExitCode -ne 0){
  $errorDetail=(@($capturedOutput|Where-Object{-not[string]::IsNullOrWhiteSpace([string]$_)})|Select-Object -Last 1)
  if($errorDetail){throw ('Git 執行失敗（錯誤碼 {0}）：{1}。{2}' -f $process.ExitCode,$Name,$errorDetail)}
  throw ('Git 執行失敗（錯誤碼 {0}）：{1}' -f $process.ExitCode,$Name)
 }
 Start-Sleep -Milliseconds 300
}

function Remove-StaleGitIndexLock {
 param([Parameter(Mandatory=$true)][string]$RepositoryPath)
 $gitDirectory=Join-Path $RepositoryPath '.git'
 $lockPath=Join-Path $gitDirectory 'index.lock'
 if(-not(Test-Path -LiteralPath $lockPath -PathType Leaf)){return}

 $activeGit=@(Get-Process -Name git -ErrorAction SilentlyContinue)
 if($activeGit.Count -gt 0){throw ('偵測到 Git 正在執行，暫不清除鎖定檔。請等待 Git 完成後再試（PID：{0}）。' -f (($activeGit.Id)-join '、'))}

 $resolvedGitDirectory=(Resolve-Path -LiteralPath $gitDirectory).Path.TrimEnd('\')
 $lockFile=Get-Item -LiteralPath $lockPath -Force
 if($lockFile.DirectoryName.TrimEnd('\') -ine $resolvedGitDirectory -or $lockFile.Name -ine 'index.lock'){
  throw ('拒絕清除位置不正確的 Git 鎖定檔：{0}' -f $lockFile.FullName)
 }

 Write-Host ('[!] 偵測到上次中斷留下的 Git 鎖定檔：{0}' -f $lockFile.FullName) -ForegroundColor Yellow
 Remove-Item -LiteralPath $lockFile.FullName -Force
 if(Test-Path -LiteralPath $lockFile.FullName){throw ('無法清除 Git 鎖定檔：{0}' -f $lockFile.FullName)}
 Write-Log -Message ('已清除殘留 Git 鎖定檔：{0}' -f $lockFile.FullName) -FileName 'Git.log'
 Write-Host '[OK] 已安全清除殘留鎖定檔，繼續更新。' -ForegroundColor Green
}

function Update-GitRepository {
 param([string]$Name,[string]$Url,[string]$Branch,[string]$Path)
 if(-not(Test-Command git)){throw '找不到 Git，請先執行 [1]。'}
 if(Test-Path (Join-Path $Path '.git')){
  $currentRemote=([string](& git -C $Path remote get-url origin 2>$null)).Trim()
  if([string]::IsNullOrWhiteSpace($currentRemote)){
   Write-Host ('[..] 建立 {0} 官方遠端：{1}' -f $Name,$Url) -ForegroundColor Cyan
   Invoke-GitMonitored @('-C',$Path,'remote','add','origin',$Url) ("設定 $Name 官方來源") $Path
  }elseif($currentRemote.TrimEnd('/') -ine $Url.TrimEnd('/')){
   Write-Host ('[!] {0} 原本的下載來源不是目前設定的官方來源：{1}' -f $Name,$currentRemote) -ForegroundColor Yellow
   Write-Host ('[..] 正在校正為：{0}' -f $Url) -ForegroundColor Cyan
   Invoke-GitMonitored @('-C',$Path,'remote','set-url','origin',$Url) ("校正 $Name 官方來源") $Path
  }
  Write-Host ('[..] 正在向遠端查詢 {0} 的最新版本...' -f $Name) -ForegroundColor Cyan
  Invoke-GitMonitored @('-C',$Path,'fetch','--progress','--prune','origin',("+refs/heads/{0}:refs/remotes/origin/{0}" -f $Branch)) ("拉取 $Name 官方更新") $Path
  Remove-StaleGitIndexLock -RepositoryPath $Path
  $localChanges=@(& git -C $Path status --porcelain=v1 --untracked-files=no 2>$null)
  $localChangeCount=@($localChanges|Where-Object{-not[string]::IsNullOrWhiteSpace([string]$_)}).Count
  $localCommit=([string](& git -C $Path rev-parse HEAD 2>$null)).Trim()
  $remoteCommit=([string](& git -C $Path rev-parse ("origin/{0}" -f $Branch) 2>$null)).Trim()
  if([string]::IsNullOrWhiteSpace($localCommit)-or[string]::IsNullOrWhiteSpace($remoteCommit)){throw ('無法讀取 {0} 的本機或遠端版本。' -f $Name)}
  $behindText=([string](& git -C $Path rev-list --count ("HEAD..origin/{0}" -f $Branch) 2>$null)).Trim()
  $behind=0;if(-not[int]::TryParse($behindText,[ref]$behind)){throw ('無法比較 {0} 的版本差異。' -f $Name)}
  if($localChangeCount -gt 0){Write-Host ('[!] {0} 有 {1} 個已追蹤檔案遭修改，將依設定直接用遠端版本覆蓋。' -f $Name,$localChangeCount) -ForegroundColor Yellow}
  Invoke-GitMonitored @('-C',$Path,'checkout','--force','-B',$Branch,("origin/{0}" -f $Branch)) ("切換並對齊 $Name 官方分支") $Path
  Invoke-GitMonitored @('-C',$Path,'reset','--hard',("origin/{0}" -f $Branch)) ("以遠端版本覆蓋 $Name") $Path
  if(Test-Path -LiteralPath (Join-Path $Path '.gitmodules') -PathType Leaf){
   Write-Host ('[..] 同步 {0} 的官方子模組...' -f $Name) -ForegroundColor Cyan
   Invoke-GitMonitored @('-C',$Path,'submodule','sync','--recursive') ("同步 $Name 子模組來源") $Path
   Invoke-GitMonitored @('-C',$Path,'submodule','update','--init','--recursive','--force','--progress') ("更新 $Name 子模組") $Path
  }
  $shortCommit=([string](& git -C $Path rev-parse --short HEAD 2>$null)).Trim()
  if($behind -gt 0){$script:MenuNotice=('{0} 已與官方同步，更新 {1} 個提交（目前 {2}），並覆蓋 {3} 個已追蹤檔案修改。' -f $Name,$behind,$shortCommit,$localChangeCount)}
  elseif($localChangeCount -gt 0){$script:MenuNotice=('{0} 已與官方最新版同步（{1}），並覆蓋 {2} 個已追蹤檔案修改。' -f $Name,$shortCommit,$localChangeCount)}
  else{$script:MenuNotice=('{0} 已與官方最新版同步（{1}）。' -f $Name,$shortCommit);Write-Host ('[OK] {0}' -f $script:MenuNotice) -ForegroundColor Green;return $false}
 } elseif(Test-Path $Path){
  # A cancelled/failed clone can leave an empty destination behind. It has no
  # user files to preserve, so remove only that verified empty folder and retry.
  $entries=@(Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop)
  if($entries.Count -eq 0){
   Write-Host ('[!] 偵測到未完成下載留下的空資料夾，將重新下載：{0}' -f $Path) -ForegroundColor Yellow
   Remove-Item -LiteralPath $Path -Force
   Update-GitRepository $Name $Url $Branch $Path
   return $true
  }
  throw ('目錄已存在但不是 Git 儲存庫：{0}' -f $Path)
 }
 else{
  Write-Host ('[..] 下載 {0}...' -f $Name)
  Invoke-GitMonitored @('clone','--progress','--verbose','--branch',$Branch,'--single-branch','--recurse-submodules',$Url,$Path) ("下載 $Name 官方原始碼") $Path
  $shortCommit=([string](& git -C $Path rev-parse --short HEAD 2>$null)).Trim()
  $script:MenuNotice=('{0} 已下載完成（目前 {1}）。' -f $Name,$shortCommit)
 }
 Write-Host ('[OK] {0}' -f $script:MenuNotice) -ForegroundColor Green
 return $true
}

function Update-ServerRepository {
 Select-Emulator
 $x=Get-CoreInfo
 Write-Host ('[..] 將 {0} 同步至官方來源：{1}（分支：{2}）' -f $x.Name,$x.Repo.Url,$x.Repo.Branch) -ForegroundColor Cyan
 Update-GitRepository $x.Name $x.Repo.Url $x.Repo.Branch $x.Path
}
function Update-ClientPatchRepository {
 $r=$script:InstallerConfig.Repositories.ClientPatch
 $path=$script:InstallerConfig.ClientPatchPath
 $legacyPath=Join-Path $script:InstallerConfig.RootPath 'ClientPatch'
 if((-not(Test-Path -LiteralPath $path)) -and (Test-Path -LiteralPath $legacyPath)){
  Write-Host ('[..] 將舊路徑搬移至新 WARP 路徑：{0} -> {1}' -f $legacyPath,$path) -ForegroundColor Cyan
  Move-Item -LiteralPath $legacyPath -Destination $path
 }
 if(Test-Path (Join-Path $path '.git')){
  $currentUrl=(& git -C $path remote get-url origin 2>$null|Select-Object -First 1)
  $currentNormalized=([string]$currentUrl).Trim().TrimEnd('/').ToLowerInvariant()
  $targetNormalized=([string]$r.Url).Trim().TrimEnd('/').ToLowerInvariant()
  if($currentNormalized -ne $targetNormalized){
   $backupPath=('{0}-old-repository-{1}' -f $path,(Get-Date -Format 'yyyyMMdd-HHmmss'))
   Write-Host ('[!] 偵測到舊 WARP 儲存庫：{0}' -f $currentUrl) -ForegroundColor Yellow
   Write-Host ('[..] 舊資料夾保留至：{0}' -f $backupPath) -ForegroundColor Cyan
   Move-Item -LiteralPath $path -Destination $backupPath
  }
 }
 Update-GitRepository 'WARP' $r.Url $r.Branch $path
}
function Update-ROenglishRERepository {$r=$script:InstallerConfig.Repositories.ROenglishRE;Update-GitRepository 'ROenglishRE' $r.Url $r.Branch $script:InstallerConfig.ROenglishREPath}
function Update-NpcBig5Repository {$r=$script:InstallerConfig.Repositories.NpcBig5;Update-GitRepository 'NPC 中文化' $r.Url $r.Branch $script:InstallerConfig.NpcBig5Path}
