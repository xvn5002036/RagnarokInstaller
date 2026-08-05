Set-StrictMode -Version 2.0

function Invoke-GitMonitored {
 param([string[]]$Arguments,[string]$Name,[string]$Destination='')
 $git=Get-Command git.exe -ErrorAction SilentlyContinue
 if(-not$git){throw '找不到 Git，請先執行 [1]。'}
 $quoted=@($Arguments|ForEach-Object{if($_ -match '[\s"]'){'"'+($_ -replace '"','\"')+'"'}else{$_}})
 Write-Log -Message ('執行：git {0}' -f ($quoted -join ' ')) -FileName 'Git.log'
 $env:GIT_PROGRESS_DELAY='0'
 $process=Start-Process -FilePath $git.Source -ArgumentList ($quoted -join ' ') -NoNewWindow -PassThru
 [void]$process.Handle
 $started=Get-Date;$lastStatus=Get-Date
 while(-not$process.HasExited){
  if(((Get-Date)-$lastStatus).TotalSeconds -ge 2){
   $sizeText=''
   if($Destination -and (Test-Path -LiteralPath $Destination)){
    $packPath=Join-Path $Destination '.git\objects\pack'
    if(Test-Path -LiteralPath $packPath){
     $bytes=(Get-ChildItem -LiteralPath $packPath -File -ErrorAction SilentlyContinue|Measure-Object Length -Sum).Sum
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
 if($process.ExitCode -ne 0){throw ('Git 執行失敗（錯誤碼 {0}）：{1}' -f $process.ExitCode,$Name)}
}

function Update-GitRepository {
 param([string]$Name,[string]$Url,[string]$Branch,[string]$Path)
 if(-not(Test-Command git)){throw '找不到 Git，請先執行 [1]。'}
 if(Test-Path (Join-Path $Path '.git')){
  Write-Host ('[..] 更新 {0}...' -f $Name)
  Invoke-GitMonitored @('-C',$Path,'fetch','--progress','--prune','origin') ("更新 $Name") $Path
  Invoke-GitMonitored @('-C',$Path,'checkout',$Branch) ("切換 $Name 分支") $Path
  Invoke-GitMonitored @('-C',$Path,'pull','--progress','--ff-only','origin',$Branch) ("合併 $Name 更新") $Path
 } elseif(Test-Path $Path){throw ('目錄已存在但不是 Git 儲存庫：{0}' -f $Path)}
 else{
  Write-Host ('[..] 下載 {0}...' -f $Name)
  Invoke-GitMonitored @('clone','--progress','--verbose','--branch',$Branch,'--single-branch',$Url,$Path) ("下載 $Name") $Path
 }
 Write-Host ('[OK] {0} 已完成。' -f $Name) -ForegroundColor Green
}

function Update-ServerRepository {Select-Emulator;$x=Get-CoreInfo;Update-GitRepository $x.Name $x.Repo.Url $x.Repo.Branch $x.Path;Pause-Console}
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
 Pause-Console
}
function Update-ROenglishRERepository {$r=$script:InstallerConfig.Repositories.ROenglishRE;Update-GitRepository 'ROenglishRE' $r.Url $r.Branch $script:InstallerConfig.ROenglishREPath;Pause-Console}
function Update-NpcBig5Repository {$r=$script:InstallerConfig.Repositories.NpcBig5;Update-GitRepository 'NPC 中文化' $r.Url $r.Branch $script:InstallerConfig.NpcBig5Path;Pause-Console}
