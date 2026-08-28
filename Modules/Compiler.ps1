Set-StrictMode -Version 2.0

<# 編譯工具：尋找 Visual Studio，檢查 rAthena 專案，並執行 Build 或 Clean。 #>
function Get-VsWherePath {
 $paths=@()
 if(${env:ProgramFiles(x86)}){$paths+=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'}
 if($env:ProgramFiles){$paths+=Join-Path $env:ProgramFiles 'Microsoft Visual Studio\Installer\vswhere.exe'}
 foreach($path in $paths){if(Test-Path -LiteralPath $path){return $path}}
 return $null
}

function Find-VisualStudioCppEnvironment {
 $installationPath=$null;$vswhere=Get-VsWherePath
 if($vswhere){
  $found=&$vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
  if($found){$installationPath=@($found)[0].Trim()}
 }
 if(-not$installationPath){
  foreach($base in @((Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\2022'),(Join-Path $env:ProgramFiles 'Microsoft Visual Studio\2022'))){
   foreach($edition in @('BuildTools','Community','Professional','Enterprise')){
    $candidate=Join-Path $base $edition
    if(Test-Path (Join-Path $candidate 'MSBuild\Current\Bin\MSBuild.exe')){$installationPath=$candidate;break}
   }
   if($installationPath){break}
  }
 }
 if(-not$installationPath){throw '找不到 Visual Studio 2022 C++ Build Tools。請先執行選項 [1]。'}
 $msbuild=Join-Path $installationPath 'MSBuild\Current\Bin\MSBuild.exe'
 $devCmd=Join-Path $installationPath 'Common7\Tools\VsDevCmd.bat'
 $vcvars=Join-Path $installationPath 'VC\Auxiliary\Build\vcvars64.bat'
 if(-not(Test-Path $msbuild)){throw ('Visual Studio 缺少 MSBuild.exe：{0}' -f $msbuild)}
 if(Test-Path $devCmd){$setup=$devCmd;$setupArgs='-arch=x64 -host_arch=x64'}
 elseif(Test-Path $vcvars){$setup=$vcvars;$setupArgs=''}
 else{throw 'Visual Studio 缺少 VsDevCmd.bat / vcvars64.bat。'}
 return [pscustomobject]@{InstallationPath=$installationPath;MSBuild=$msbuild;SetupScript=$setup;SetupArguments=$setupArgs}
}

function Test-VisualStudioProjects {
 param($Core)
 $solution=Join-Path $Core.Path 'rAthena.sln'
 if(-not(Test-Path $solution)){throw ('找不到 {0} 的 Visual Studio Solution：{1}' -f $Core.Name,$solution)}
 $required=@(
  'src\login\login-server.vcxproj',
  'src\char\char-server.vcxproj',
  'src\map\map-server.vcxproj',
  'src\web\web-server.vcxproj',
  'src\common\common.vcxproj',
  '3rdparty\libconfig\libconfig.vcxproj'
 )
 $missing=@($required|Where-Object{-not(Test-Path (Join-Path $Core.Path $_))})
 if($missing.Count){throw ('{0} 缺少必要的 Visual Studio 專案檔：{1}。請重新執行 [3] 下載完整原始碼。' -f $Core.Name,($missing -join '、'))}
 $solutionText=[IO.File]::ReadAllText($solution,[Text.Encoding]::UTF8)
 if($solutionText -notmatch [regex]::Escape('Release|x64')){throw ('{0} 的 rAthena.sln 不含 Release|x64 組態。' -f $Core.Name)}
 return $solution
}

function Ensure-RagnarokRuntimeDependencies {
 $runtimeDll=Join-Path $env:WINDIR 'System32\MSVCR110.dll'
 if(Test-Path -LiteralPath $runtimeDll){
  Write-Host '[OK] Visual C++ 2012 x64 Runtime：已安裝' -ForegroundColor Green
  return
 }

 Write-Host '[!] 伺服器的 pcre8.dll 需要 MSVCR110.dll。' -ForegroundColor Yellow
 Write-Host '[..] 正在安裝 Visual C++ 2012 x64 Runtime（vcredist2012）...' -ForegroundColor Cyan
 $choco=Get-Command choco.exe -ErrorAction SilentlyContinue
 if(-not$choco){throw '缺少 Visual C++ 2012 Runtime，且找不到 Chocolatey。請先執行選項 [1] 安裝開發環境。'}
 $process=Start-Process -FilePath $choco.Source -ArgumentList 'upgrade vcredist2012 -y --no-progress' -NoNewWindow -PassThru
 [void]$process.Handle;$started=Get-Date;$frame=0;$width=24
 while(-not$process.HasExited){
  $position=$frame%($width-4)
  $bar=(' ' * $position)+'====>'+(' ' * ($width-$position-5))
  Write-Host ("`r[{0}] 安裝 VC++ 2012 Runtime，PID {1}，耗時 {2:hh\:mm\:ss}      " -f $bar,$process.Id,((Get-Date)-$started)) -NoNewline -ForegroundColor Cyan
  $frame++;Start-Sleep -Milliseconds 500;$process.Refresh()
 }
 Write-Host '';$process.WaitForExit();$process.Refresh()
 if($process.ExitCode -ne 0){throw ('Visual C++ 2012 Runtime 安裝失敗（錯誤碼 {0}）。' -f $process.ExitCode)}
 if(-not(Test-Path -LiteralPath $runtimeDll)){throw ('Visual C++ 2012 Runtime 安裝命令已完成，但仍找不到：{0}' -f $runtimeDll)}
 Write-Host '[OK] Visual C++ 2012 x64 Runtime 安裝完成。' -ForegroundColor Green
}

function Invoke-MSBuildMonitored {
 param($VisualStudio,[string]$Solution,[string]$Target,[string]$CorePath)
 $logPath=Join-Path $script:LogsPath 'Compile.log'
 $arguments=@(
  ('"{0}"' -f $Solution),('/t:'+$Target),'/m:2','/nr:false','/nologo','/noconsolelogger',
  '/p:Configuration=Release','/p:Platform=x64','/p:PreferredToolArchitecture=x64',
  '/fl',('/flp:logfile="{0}";verbosity=normal;encoding=UTF-8' -f $logPath)
 ) -join ' '
 Write-Log -Message ('執行：MSBuild {0}' -f $arguments) -FileName 'Compile.log'
 $process=Start-Process -FilePath $VisualStudio.MSBuild -ArgumentList $arguments -WorkingDirectory $CorePath -NoNewWindow -PassThru
 [void]$process.Handle;$started=Get-Date;$frame=0
 Write-Host '[i] 階段對照：Step 1 分析專案 -> Step 2 編譯 C++ -> Step 3 產生伺服器 EXE' -ForegroundColor Cyan
 Write-Host ('[i] 核心執行路徑：{0}' -f $CorePath) -ForegroundColor Cyan
 $activityTitle=switch($Target){'Clean'{'Ragnarok Server Clean'}'Rebuild'{'Ragnarok Server Rebuild'}default{'Ragnarok Server Build'}}
 $currentBuildItem='Waiting for compiler activity...'
 $shownFileNames=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 while(-not$process.HasExited){
  $compilerCount=@(Get-Process cl -ErrorAction SilentlyContinue).Count
  $linkerCount=@(Get-Process link -ErrorAction SilentlyContinue).Count
  if($Target-eq'Clean'){
   $step='Cleaning old build outputs'
   $explanation='Removing old EXE, library and intermediate files'
  }elseif($linkerCount){
   $step='Step 3/3 - Creating server EXE files'
   $explanation='Linking login, char, map and web server executables'
  }elseif($compilerCount){
   $step=('Step 2/3 - Compiling C++ - Workers: {0}' -f $compilerCount)
   $explanation='Converting source code into program components'
  }else{
   $step='Step 1/3 - Analyzing projects'
   $explanation='Checking which files need to be compiled'
  }
  try{
   $recentLines=@(Get-Content -LiteralPath $logPath -Tail 250 -ErrorAction SilentlyContinue)
   $newFileNames=New-Object 'Collections.Generic.List[string]'
   foreach($recentLine in $recentLines){
    $fileMatches=[regex]::Matches([string]$recentLine,'(?i)([A-Za-z0-9_.-]+\.(?:cpp|c|cc|cxx|vcxproj|lib|exe|dll))')
    foreach($fileMatch in $fileMatches){
     $fileName=$fileMatch.Groups[1].Value
     if($shownFileNames.Add($fileName)){[void]$newFileNames.Add($fileName)}
    }
   }
   if($newFileNames.Count){
    Write-Progress -Id 1 -Activity $activityTitle -Completed
    foreach($fileName in @($newFileNames|Select-Object -Last 12)){Write-Host ('    {0}' -f $fileName) -ForegroundColor White}
   }
   for($lineIndex=$recentLines.Count-1;$lineIndex-ge0;$lineIndex--){
    $line=[string]$recentLines[$lineIndex]
    if($linkerCount -and $line-match '(?i)([A-Z]:\\[^\r\n]*?\.(?:exe|dll))'){
     $activePath=$Matches[1].Trim();if($activePath.StartsWith($CorePath,[StringComparison]::OrdinalIgnoreCase)){$activePath=$activePath.Substring($CorePath.Length).TrimStart('\')}
     $currentBuildItem=('Creating EXE: {0}' -f $activePath);break
    }
    if($compilerCount -and $line-match '(?i)((?:\.\.[\\/]|[A-Z]:\\|src[\\/]|3rdparty[\\/])[^''"\)\r\n]*?\.(?:cpp|c|cc|cxx))'){
     $activePath=$Matches[1].Trim();if($activePath.StartsWith($CorePath,[StringComparison]::OrdinalIgnoreCase)){$activePath=$activePath.Substring($CorePath.Length).TrimStart('\')}
     $currentBuildItem=('Compiling: {0}' -f $activePath);break
    }
   }
  }catch{}
  $elapsed=(Get-Date)-$started
  $operation=if($currentBuildItem-eq'Waiting for compiler activity...'){('{0} | Path: {1}' -f $explanation,$CorePath)}else{$currentBuildItem}
  Write-Progress -Id 1 -Activity $activityTitle -Status (('{0} | Elapsed: {1:hh\:mm\:ss}' -f $step,$elapsed)) -CurrentOperation $operation -PercentComplete -1
  $frame++;Start-Sleep -Milliseconds 500;$process.Refresh()
 }
 $process.WaitForExit();$process.Refresh();$elapsed=(Get-Date)-$started
 Write-Progress -Id 1 -Activity $activityTitle -Completed
 if($process.ExitCode -ne 0){throw ('Visual Studio MSBuild 失敗（錯誤碼 {0}）。請查看 Compile.log。' -f $process.ExitCode)}
 if($Target-eq'Clean'){Write-Host ('[OK] 舊的編譯結果已清除，總耗時 {0:hh\:mm\:ss}。需要產生伺服器 EXE 時請執行 [4]。' -f $elapsed) -ForegroundColor Green}
 else{Write-Host ('[OK] 伺服器編譯完成，總耗時 {0:hh\:mm\:ss}。' -f $elapsed) -ForegroundColor Green}
}

function Invoke-VisualStudioBuild {
 param([ValidateSet('Build','Clean','Rebuild')][string]$Target='Build')
 # rAthena 與 PandasWS 都使用相容的 Visual Studio Solution 與 MSBuild 組態。
 $core=Get-CoreInfo
 if(-not(Test-Path $core.Path)){throw ('核心目錄不存在：{0}' -f $core.Path)}
 Ensure-RagnarokRuntimeDependencies
 $solution=Test-VisualStudioProjects $core
 $vs=Find-VisualStudioCppEnvironment
 Write-Host ('[OK] Visual Studio：{0}' -f $vs.InstallationPath) -ForegroundColor Green
 Write-Host ('[OK] MSBuild：{0}' -f $vs.MSBuild) -ForegroundColor Green
 Write-Host ('[OK] Solution：{0}' -f $solution) -ForegroundColor Green
 Write-Host '[OK] 組態：Release | x64' -ForegroundColor Green

 $compileLog=Join-Path $script:LogsPath 'Compile.log'
 if(Test-Path $compileLog){Move-Item $compileLog (Join-Path $script:LogsPath ('Compile-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))) -Force}

 # 此指令等同在 Visual Studio 選擇 Release/x64 後執行 Build、Clean 或 Rebuild。
 Invoke-MSBuildMonitored $vs $solution $Target $core.Path
 Write-Host ('[OK] {0} Visual Studio {1} 完成，核心位置：{2}' -f $core.Name,$Target,$core.Path) -ForegroundColor Green
}

function Build-RagnarokServer {
 Write-Host '[i] 正在進行快速增量編譯：MSBuild 會自動重新編譯所有已修改及受影響的檔案。' -ForegroundColor Cyan
 Write-Host '[i] 一般修改程式後請直接按 [4]；不必先按 [5]，產出的伺服器執行檔結果相同。' -ForegroundColor Cyan
 Invoke-VisualStudioBuild -Target Build
}
function Remove-RagnarokBuildArtifacts {
 param([Parameter(Mandatory=$true)][string]$CorePath)
 $resolvedCore=[IO.Path]::GetFullPath($CorePath).TrimEnd('\')
 if(-not(Test-Path -LiteralPath $resolvedCore -PathType Container)){throw ('核心目錄不存在：{0}' -f $resolvedCore)}
 # 不可在伺服器使用檔案時清除，避免留下半套執行檔。
 $running=@(Get-Process -Name 'login-server','char-server','map-server','web-server' -ErrorAction SilentlyContinue)
 if($running.Count){throw '伺服器仍在執行中。請先按 [H] 停止伺服器，再執行 [5]。'}

 $removed=0
 # rAthena / PandasWS 會將這些編譯輸出放在核心根目錄；不包含 pcre8.dll、libmysql.dll
 # 等下載原始碼本身提供的必要執行期 DLL。
 $artifactExtensions=@('.exe','.pdb','.ilk','.lib','.exp')
 foreach($file in @(Get-ChildItem -LiteralPath $resolvedCore -File -Force | Where-Object {$artifactExtensions -contains $_.Extension.ToLowerInvariant()})){
  Remove-Item -LiteralPath $file.FullName -Force
  $removed++
 }
 # Visual Studio 的中間檔在每個專案的 .vs\build 內；僅刪除此明確的編譯快取目錄，
 # 不碰 .vs 其他使用者設定，也不碰任何原始碼目錄。
 $buildDirectories=@(Get-ChildItem -LiteralPath $resolvedCore -Directory -Recurse -Force | Where-Object {
  $_.Name -eq 'build' -and $_.Parent.Name -eq '.vs' -and $_.FullName.StartsWith($resolvedCore+'\',[StringComparison]::OrdinalIgnoreCase)
 })
 foreach($directory in $buildDirectories){
  Remove-Item -LiteralPath $directory.FullName -Recurse -Force
  $removed++
 }
 Write-Host ('[OK] 已移除 {0} 個編譯產物／快取目錄；核心已回到未編譯狀態。' -f $removed) -ForegroundColor Green
}
function Clear-RagnarokBuild {
 $core=Get-CoreInfo
 Write-Host '[!] 此操作會將目前核心還原成「未編譯」狀態，下一次 [4] 將進行完整編譯。' -ForegroundColor Yellow
 Write-Host '[i] 會清除伺服器 EXE、PDB、LIB、EXP 與 .vs\build 中間檔；不會刪除原始碼、設定或資料庫。' -ForegroundColor Cyan
 $confirmation=Read-Host ('確定清除 {0} 的所有編譯產物？輸入 CLEAN 確認' -f $core.Name)
 if($confirmation -ne 'CLEAN'){Write-Host '[-] 已取消清除，保留快速增量編譯快取。' -ForegroundColor DarkYellow;return}
 Invoke-VisualStudioBuild -Target Clean
 Remove-RagnarokBuildArtifacts -CorePath $core.Path
}
