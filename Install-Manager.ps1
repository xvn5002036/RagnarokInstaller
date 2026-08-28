#requires -Version 5.1
[CmdletBinding()]param()
Set-StrictMode -Version 2.0;$ErrorActionPreference='Stop'
$script:AppPath=Split-Path -Parent $MyInvocation.MyCommand.Path;$script:ConfigPath=Join-Path $script:AppPath 'Config';$script:LogsPath=Join-Path $script:AppPath 'Logs';$script:ConfigFile=Join-Path $script:ConfigPath 'installer.json';$script:MenuNotice='';$script:ShowSystemDetails=$false
foreach($m in @('Logger.ps1','Common.ps1','UI.ps1','Config.ps1','Environment.ps1','Git.ps1','Database.ps1','ConfigEditor.ps1','Compiler.ps1','Localization.ps1','PlayerAdmin.ps1','Service.ps1')){. (Join-Path (Join-Path $script:AppPath 'Modules') $m)}
try{Assert-Administrator;$script:InstallerConfig=Get-InstallerConfig;Initialize-ApplicationDirectories;Initialize-FirstRunCoreSelection;Write-Log 'Ragnarok 安裝管理中心已啟動。'}catch{Write-Host ('[X] 初始化失敗：{0}' -f $_.Exception.Message) -ForegroundColor Red;exit 1}
function Show-MainMenu {
 Clear-Host;$core=Get-CoreInfo
 Write-Host '========================================================' -ForegroundColor Cyan
 Write-Host '       Ragnarok 安裝管理中心 v6.0 精裝版' -ForegroundColor Cyan
 Write-Host '========================================================' -ForegroundColor Cyan
 Write-Host ('程式位置：{0}' -f $script:AppPath) -ForegroundColor DarkGray
 Write-Host ('目前核心：{0}    安裝位置：{1}' -f $core.Name,$core.Path)
 $managerVersion=if(Test-Path -LiteralPath (Join-Path $script:AppPath 'VERSION.txt')){([IO.File]::ReadAllText((Join-Path $script:AppPath 'VERSION.txt'))).Trim()}else{'未知'}
 Write-Host ('管理中心版本：{0}' -f $managerVersion) -ForegroundColor DarkGray
 $coreVersion=Get-GitRepositoryVersionStatus -RepositoryPath $core.Path -Branch $core.Repo.Branch
 if($coreVersion){
  Write-Host ('核心 Git 版本：{0} @ {1}    提交日期：{2}' -f $coreVersion.Branch,$coreVersion.Commit,$coreVersion.CommitDate)
  if($coreVersion.Synchronized){Write-Host ('官方同步狀態：[OK] 已拉取完成（origin/{0} @ {1}）' -f $core.Repo.Branch,$coreVersion.RemoteCommit) -ForegroundColor Green}
  else{Write-Host ('官方同步狀態：[!] 本機版本尚未對齊 origin/{0}，請執行 [3]。' -f $core.Repo.Branch) -ForegroundColor Yellow}
 }else{Write-Host '核心 Git 版本：尚未下載或無法讀取' -ForegroundColor DarkYellow}
 if(-not[string]::IsNullOrWhiteSpace($script:MenuNotice)){Write-Host ('最新狀態：{0}' -f $script:MenuNotice) -ForegroundColor Green;Write-Host '';$script:MenuNotice=''}
 Write-Host '';Show-CompactSystemStatus;Write-Host ''
 Write-Host '【環境管理】' -ForegroundColor Yellow
 Write-Host '[1] 安裝 / 更新開發環境';Write-Host '    安裝 Git、Python、.NET 8 SDK、Visual Studio Build Tools 等工具。' -ForegroundColor DarkGray
 Write-Host '[2] 安裝 / 更新 MariaDB';Write-Host '    安裝或修復 MariaDB 資料庫服務，供遊戲伺服器儲存帳號與角色資料。' -ForegroundColor DarkGray;Write-Host ''
 Write-Host '【伺服器管理】' -ForegroundColor Yellow
 Write-Host '[S] 切換目前核心';Write-Host '    只切換 rAthena／PandasWS 的工作路徑，不下載或更新檔案。' -ForegroundColor DarkGray
 Write-Host '[3] 與官方同步 rAthena / PandasWS';Write-Host '    選擇核心後拉取官方最新提交，並將已追蹤的原始碼更新為官方版本。' -ForegroundColor DarkGray
 Write-Host '[4] 快速增量編譯目前核心';Write-Host '    改完程式後直接使用；只編譯已變更與相依檔案，結果和完整編譯相同，速度最快。' -ForegroundColor DarkGray
 Write-Host '[5] 還原目前核心為未編譯狀態（通常不需要）';Write-Host '    清除伺服器 EXE 與所有編譯快取；下一次 [4] 會像第一次一樣完整編譯。僅在更新核心、編譯異常或需要完整重建時使用。' -ForegroundColor DarkYellow;Write-Host ''
 Write-Host '【客戶端與中文化】' -ForegroundColor Yellow
 Write-Host '[6] 更新 WARP';Write-Host '    下載或更新 WARP 客戶端補丁專案。' -ForegroundColor DarkGray
 Write-Host '[D] 更新 ROenglishRE';Write-Host '    下載或更新 ROenglishRE 英文化資源。' -ForegroundColor DarkGray
 Write-Host '[E] 更新 NPC 腳本中文化';Write-Host '    下載或更新繁體中文 NPC 腳本資源。' -ForegroundColor DarkGray
 Write-Host '[F] 套用中文化';Write-Host '    將已下載的中文化資源套用到目前伺服器核心。' -ForegroundColor DarkGray;Write-Host ''
 Write-Host '【資料庫】' -ForegroundColor Yellow
 Write-Host '[7] 建立 / 匯入資料庫';Write-Host '    建立遊戲資料庫並匯入目前 rAthena 或 PandasWS 核心需要的 SQL；已有資料時可選擇保留。' -ForegroundColor DarkGray
 Write-Host '[8] 初始化目前核心設定';Write-Host '    寫入目前 rAthena 或 PandasWS 的資料庫連線、伺服器通訊帳密與 PACKETVER 等必要設定。' -ForegroundColor DarkGray;Write-Host ''
 Write-Host '【玩家管理後台】' -ForegroundColor Yellow
 Write-Host '[I] 安裝 / 更新玩家管理後台';Write-Host '    套用內建最新版，並準備 Player Admin 專用的 .NET 8 執行環境。' -ForegroundColor DarkGray
 Write-Host '[J] 啟動玩家管理後台';Write-Host '    只啟動管理介面；不會下載任何檔案。若尚未準備環境請先按 [I]。' -ForegroundColor DarkGray;Write-Host ''
 Write-Host '【工具】' -ForegroundColor Yellow
 Write-Host '[9] 顯示系統資訊';Write-Host '    查看目前核心、安裝路徑、資料庫、Python 與伺服器執行檔狀態。' -ForegroundColor DarkGray
 Write-Host '[A] 開啟 Logs';Write-Host '    在檔案總管開啟安裝管理中心的記錄檔資料夾。' -ForegroundColor DarkGray
 Write-Host '[L] 清除 Logs';Write-Host '    刪除安裝管理中心產生的舊記錄檔。' -ForegroundColor DarkGray
 Write-Host '[B] 全部移除';Write-Host '    移除 Ragnarok 伺服器的安裝內容；執行前會要求確認。' -ForegroundColor DarkYellow
 Write-Host '[C] 啟動伺服器';Write-Host '    啟動目前選擇的 rAthena 或 PandasWS；PandasWS 會依序啟動四個伺服器程式。' -ForegroundColor DarkGray
 Write-Host '[H] 停止伺服器';Write-Host '    停止目前正在執行的 Ragnarok 伺服器程式。' -ForegroundColor DarkGray
 Write-Host '[G] 一鍵初始化（不自動啟動）';Write-Host '    依序準備環境、核心、資料庫與設定，完成後不啟動伺服器。' -ForegroundColor DarkGray
 Write-Host '[0] 離開';Write-Host '    關閉 Ragnarok 安裝管理中心。' -ForegroundColor DarkGray
 Write-Host '========================================================' -ForegroundColor Cyan
 if($script:ShowSystemDetails){Show-InstallerConfig;Write-Host '========================================================' -ForegroundColor Cyan;$script:ShowSystemDetails=$false}
}
$run=$true;while($run){Show-MainMenu;$choice=Read-MenuChoice;try{switch($choice){'1'{Install-DevelopmentEnvironment}'2'{Install-MariaDBEnvironment}'S'{Select-Emulator}'3'{Update-ServerRepository}'4'{Build-RagnarokServer}'5'{Clear-RagnarokBuild}'6'{Update-ClientPatchRepository}'7'{Initialize-RagnarokDatabase}'8'{Initialize-ServerConfig}'9'{$script:ShowSystemDetails=$true}'A'{Open-LogsFolder}'L'{Clear-InstallerLogs}'B'{Remove-RagnarokInstallation}'C'{Start-RagnarokServer}'H'{Stop-RagnarokServer}'D'{Update-ROenglishRERepository}'E'{Update-NpcBig5Repository}'F'{Apply-RagnarokLocalization}'G'{Invoke-OneClickSetup}'I'{Install-OrUpdatePlayerAdmin}'J'{Start-PlayerAdmin}'0'{$run=$false}default{Write-Host '[X] 無效選項。' -ForegroundColor Red;Start-Sleep 1}}}catch{Write-Host ('[X] {0}' -f $_.Exception.Message) -ForegroundColor Red;Write-Log $_.Exception.ToString() 'ERROR';Start-Sleep 2}}
Write-Log 'Ragnarok 安裝管理中心已結束。'
