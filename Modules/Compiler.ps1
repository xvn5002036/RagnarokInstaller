Set-StrictMode -Version 2.0

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

function Test-OfficialVisualStudioProjects {
 param($Core)
 $solution=Join-Path $Core.Path 'rAthena.sln'
 if(-not(Test-Path $solution)){throw ('找不到 rAthena 官方 Solution：{0}' -f $solution)}
 $required=@(
  'src\login\login-server.vcxproj',
  'src\char\char-server.vcxproj',
  'src\map\map-server.vcxproj',
  'src\web\web-server.vcxproj',
  'src\common\common.vcxproj',
  '3rdparty\libconfig\libconfig.vcxproj'
 )
 $missing=@($required|Where-Object{-not(Test-Path (Join-Path $Core.Path $_))})
 if($missing.Count){throw ('rAthena 缺少官方 Visual Studio 專案檔：{0}。請重新執行 [3] 下載完整原始碼。' -f ($missing -join '、'))}
 $solutionText=[IO.File]::ReadAllText($solution,[Text.Encoding]::UTF8)
 if($solutionText -notmatch [regex]::Escape('Release|x64')){throw 'rAthena.sln 不含 Release|x64 組態。'}
 return $solution
}

function Ensure-RAthenaRuntimeDependencies {
 $runtimeDll=Join-Path $env:WINDIR 'System32\MSVCR110.dll'
 if(Test-Path -LiteralPath $runtimeDll){
  Write-Host '[OK] Visual C++ 2012 x64 Runtime：已安裝' -ForegroundColor Green
  return
 }

 Write-Host '[!] rAthena 的 pcre8.dll 需要 MSVCR110.dll。' -ForegroundColor Yellow
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
 $activityTitle=if($Target-eq'Rebuild'){'Ragnarok Server Rebuild'}else{'Ragnarok Server Build'}
 $currentBuildItem='Waiting for compiler activity...'
 $shownFileNames=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 while(-not$process.HasExited){
  $compilerCount=@(Get-Process cl -ErrorAction SilentlyContinue).Count
  $linkerCount=@(Get-Process link -ErrorAction SilentlyContinue).Count
  if($linkerCount){
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
 Write-Host ('[OK] 伺服器編譯完成，總耗時 {0:hh\:mm\:ss}。' -f $elapsed) -ForegroundColor Green
}

function Invoke-VisualStudioBuild {
 param([switch]$Clean)
 # 使用 rAthena 官方 Visual Studio Solution 與 MSBuild。
 $core=Get-CoreInfo
 if($core.Name -ne 'rAthena'){throw '目前的 Visual Studio Solution 編譯流程僅適用 rAthena。請先選擇 rAthena。'}
 if(-not(Test-Path $core.Path)){throw ('核心目錄不存在：{0}' -f $core.Path)}
 Ensure-RAthenaRuntimeDependencies
 $solution=Test-OfficialVisualStudioProjects $core
 $vs=Find-VisualStudioCppEnvironment
 Write-Host ('[OK] Visual Studio：{0}' -f $vs.InstallationPath) -ForegroundColor Green
 Write-Host ('[OK] MSBuild：{0}' -f $vs.MSBuild) -ForegroundColor Green
 Write-Host ('[OK] Solution：{0}' -f $solution) -ForegroundColor Green
 Write-Host '[OK] 組態：Release | x64' -ForegroundColor Green

 $compileLog=Join-Path $script:LogsPath 'Compile.log'
 if(Test-Path $compileLog){Move-Item $compileLog (Join-Path $script:LogsPath ('Compile-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))) -Force}

 $target=if($Clean){'Rebuild'}else{'Build'}
 # 此指令等同在 Visual Studio 選擇 Release/x64 後執行建置方案或重建方案。
 Invoke-MSBuildMonitored $vs $solution $target $core.Path
 Write-Host ('[OK] Visual Studio {0} 完成，輸出位置：{1}' -f $target,$core.Path) -ForegroundColor Green
}

function Build-RagnarokServer {Invoke-VisualStudioBuild}
function Rebuild-RagnarokServer {Invoke-VisualStudioBuild -Clean}
