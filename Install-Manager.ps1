#requires -Version 5.1
[CmdletBinding()]param()
Set-StrictMode -Version 2.0;$ErrorActionPreference='Stop'
$script:AppPath=Split-Path -Parent $MyInvocation.MyCommand.Path;$script:ConfigPath=Join-Path $script:AppPath 'Config';$script:LogsPath=Join-Path $script:AppPath 'Logs';$script:ConfigFile=Join-Path $script:ConfigPath 'installer.json';$script:MenuNotice='';$script:ShowSystemDetails=$false
foreach($m in @('Logger.ps1','Common.ps1','UI.ps1','Config.ps1','Environment.ps1','Git.ps1','Database.ps1','ConfigEditor.ps1','Compiler.ps1','Localization.ps1','Service.ps1')){. (Join-Path (Join-Path $script:AppPath 'Modules') $m)}
try{Assert-Administrator;$script:InstallerConfig=Get-InstallerConfig;Initialize-ApplicationDirectories;Write-Log 'Ragnarok 安裝管理中心已啟動。'}catch{Write-Host ('[X] 初始化失敗：{0}' -f $_.Exception.Message) -ForegroundColor Red;exit 1}
function Show-MainMenu {
 Clear-Host;$core=Get-CoreInfo
 Write-Host '========================================================' -ForegroundColor Cyan
 Write-Host '       Ragnarok 安裝管理中心 v6.0 精裝版' -ForegroundColor Cyan
 Write-Host '========================================================' -ForegroundColor Cyan
 Write-Host ('程式位置：{0}' -f $script:AppPath) -ForegroundColor DarkGray
 Write-Host ('目前核心：{0}    安裝位置：{1}' -f $core.Name,$core.Path)
 if(-not[string]::IsNullOrWhiteSpace($script:MenuNotice)){Write-Host ('最新狀態：{0}' -f $script:MenuNotice) -ForegroundColor Green;Write-Host '';$script:MenuNotice=''}
 Write-Host '';Show-CompactSystemStatus;Write-Host ''
 Write-Host '【環境管理】' -ForegroundColor Yellow
 Write-Host '[1] 安裝 / 更新開發環境';Write-Host '    安裝編譯伺服器所需的 Git、Python、Visual Studio Build Tools 等工具。' -ForegroundColor DarkGray
 Write-Host '[2] 安裝 / 更新 MariaDB';Write-Host '    安裝或修復 MariaDB 資料庫服務，供遊戲伺服器儲存帳號與角色資料。' -ForegroundColor DarkGray;Write-Host ''
 Write-Host '【伺服器管理】' -ForegroundColor Yellow
 Write-Host '[3] 更新 rAthena / PandasWS';Write-Host '    選擇核心，並從 GitHub 下載或更新它的原始碼。' -ForegroundColor DarkGray
 Write-Host '[4] 編譯目前核心';Write-Host '    使用 Visual Studio 建置目前核心，產生伺服器執行檔。' -ForegroundColor DarkGray
 Write-Host '[5] 清除目前核心的編譯結果';Write-Host '    只清除舊的執行檔與中間檔；需要重新編譯時請再執行 [4]。' -ForegroundColor DarkGray;Write-Host ''
 Write-Host '【客戶端與中文化】' -ForegroundColor Yellow
 Write-Host '[6] 更新 WARP';Write-Host '    下載或更新 WARP 客戶端補丁專案。' -ForegroundColor DarkGray
 Write-Host '[D] 更新 ROenglishRE';Write-Host '    下載或更新 ROenglishRE 英文化資源。' -ForegroundColor DarkGray
 Write-Host '[E] 更新 NPC 腳本中文化';Write-Host '    下載或更新繁體中文 NPC 腳本資源。' -ForegroundColor DarkGray
 Write-Host '[F] 套用中文化';Write-Host '    將已下載的中文化資源套用到目前伺服器核心。' -ForegroundColor DarkGray;Write-Host ''
 Write-Host '【資料庫】' -ForegroundColor Yellow
 Write-Host '[7] 建立 / 匯入資料庫';Write-Host '    建立遊戲資料庫並匯入核心需要的 SQL；已有資料時可選擇保留。' -ForegroundColor DarkGray
 Write-Host '[8] 初始化 rAthena 設定';Write-Host '    寫入資料庫連線、伺服器通訊帳密與 PACKETVER 等必要設定。' -ForegroundColor DarkGray;Write-Host ''
 Write-Host '【工具】' -ForegroundColor Yellow
 Write-Host '[9] 顯示系統資訊';Write-Host '    查看目前核心、安裝路徑、資料庫、Python 與伺服器執行檔狀態。' -ForegroundColor DarkGray
 Write-Host '[A] 開啟 Logs';Write-Host '    在檔案總管開啟安裝管理中心的記錄檔資料夾。' -ForegroundColor DarkGray
 Write-Host '[L] 清除 Logs';Write-Host '    刪除安裝管理中心產生的舊記錄檔。' -ForegroundColor DarkGray
 Write-Host '[B] 全部移除';Write-Host '    移除 Ragnarok 伺服器的安裝內容；執行前會要求確認。' -ForegroundColor DarkYellow
 Write-Host '[C] 啟動伺服器';Write-Host '    啟動 login、char、map 與 web 等伺服器程式。' -ForegroundColor DarkGray
 Write-Host '[H] 停止伺服器';Write-Host '    停止目前正在執行的 Ragnarok 伺服器程式。' -ForegroundColor DarkGray
 Write-Host '[G] 一鍵初始化（不自動啟動）';Write-Host '    依序準備環境、核心、資料庫與設定，完成後不啟動伺服器。' -ForegroundColor DarkGray
 Write-Host '[0] 離開';Write-Host '    關閉 Ragnarok 安裝管理中心。' -ForegroundColor DarkGray
 Write-Host '========================================================' -ForegroundColor Cyan
 if($script:ShowSystemDetails){Show-InstallerConfig;Write-Host '========================================================' -ForegroundColor Cyan;$script:ShowSystemDetails=$false}
}
$run=$true;while($run){Show-MainMenu;$choice=Read-MenuChoice;try{switch($choice){'1'{Install-DevelopmentEnvironment}'2'{Install-MariaDBEnvironment}'3'{Update-ServerRepository}'4'{Build-RagnarokServer}'5'{Clear-RagnarokBuild}'6'{Update-ClientPatchRepository}'7'{Initialize-RagnarokDatabase}'8'{Initialize-RAthenaConfig}'9'{$script:ShowSystemDetails=$true}'A'{Open-LogsFolder}'L'{Clear-InstallerLogs}'B'{Remove-RagnarokInstallation}'C'{Start-RagnarokServer}'H'{Stop-RagnarokServer}'D'{Update-ROenglishRERepository}'E'{Update-NpcBig5Repository}'F'{Apply-RagnarokLocalization}'G'{Invoke-OneClickSetup}'0'{$run=$false}default{Write-Host '[X] 無效選項。' -ForegroundColor Red;Start-Sleep 1}}}catch{Write-Host ('[X] {0}' -f $_.Exception.Message) -ForegroundColor Red;Write-Log $_.Exception.ToString() 'ERROR';Start-Sleep 2}}
Write-Log 'Ragnarok 安裝管理中心已結束。'
