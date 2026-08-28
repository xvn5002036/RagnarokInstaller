Set-StrictMode -Version 2.0
<#
此模組負責安裝管理中心的畫面、狀態板與記錄檔操作。
不會下載、安裝或變更遊戲資料；真正的工作由其他模組執行。
#>
function Get-DisplayMark {param([bool]$Value);if($Value){return '[OK]'};return '[ ] '}
function Show-CompactSystemStatus {
 $core=Get-CoreInfo;$maria=Get-MariaDbService
 Write-Host '【目前狀態】' -ForegroundColor Yellow
 Write-Host ('{0} Git' -f (Get-DisplayMark (Test-Command git)))
 $python=Get-InstalledPythonVersion;if($python){Write-Host ('[OK] Python：{0}' -f $python.Version)}else{Write-Host '[ ]  Python：未安裝'}
 try{$null=Find-VisualStudioCppEnvironment;Write-Host '[OK] Visual Studio C++ Build Tools'}catch{Write-Host '[ ]  Visual Studio C++ Build Tools'}
 $mariaText=if($maria){if($maria.State -eq 'Running'){"執行中（服務：$($maria.Name)）"}else{"已安裝但未執行（服務：$($maria.Name)）"}}else{'未安裝'}
 Write-Host ('{0} MariaDB：{1}' -f (Get-DisplayMark ($null -ne $maria)),$mariaText)
 Write-Host ('{0} {1} 原始碼' -f (Get-DisplayMark (Test-Path (Join-Path $core.Path '.git'))),$core.Name)
 Write-Host ('{0} 玩家管理後台' -f (Get-DisplayMark (Test-Path (Join-Path $script:InstallerConfig.PlayerAdminPath 'RathenaPlayerAdmin.csproj'))))
}
function New-StatusBoard {param([string[]]$Steps);$board=[ordered]@{};foreach($step in $Steps){$board[$step]='Pending'};return $board}
function Show-StatusBoard {
 param([System.Collections.IDictionary]$Board,[string]$CurrentWork)
 Clear-Host;Write-Host '========================================================' -ForegroundColor Cyan;Write-Host '       Ragnarok 安裝管理中心 v6.0 精裝版' -ForegroundColor Cyan;Write-Host '========================================================' -ForegroundColor Cyan
 Write-Host ('目前工作：{0}' -f $CurrentWork) -ForegroundColor Yellow;Write-Host ''
 foreach($name in $Board.Keys){$mark=switch($Board[$name]){'Running'{'[..]'}'Done'{'[OK]'}'Failed'{'[X]'}'Skipped'{'[-]'}default{'[ ]'}};$color=switch($Board[$name]){'Running'{'Cyan'}'Done'{'Green'}'Failed'{'Red'}'Skipped'{'DarkGray'}default{'Gray'}};Write-Host ('{0} {1}' -f $mark,$name) -ForegroundColor $color}
 Write-Host '========================================================' -ForegroundColor Cyan
}
function Invoke-StatusStep {param([System.Collections.IDictionary]$Board,[string]$Name,[scriptblock]$Action);$Board[$Name]='Running';Show-StatusBoard $Board ('正在執行：'+$Name);try{&$Action;$Board[$Name]='Done';Show-StatusBoard $Board ('已完成：'+$Name)}catch{$Board[$Name]='Failed';Show-StatusBoard $Board ('執行失敗：'+$Name);throw}}
function Clear-InstallerLogs {
 Initialize-LogDirectory $script:LogsPath;$files=Get-ChildItem -LiteralPath $script:LogsPath -File -Filter '*.log' -ErrorAction SilentlyContinue
 if(-not$files){Write-Host '[-] 沒有可清除的 Log。' -ForegroundColor DarkYellow;return}
 $answer=Read-Host ('將刪除 {0} 個 Log，輸入 CLEAR 確認' -f @($files).Count);if($answer -cne 'CLEAR'){Write-Host '[-] 已取消。';return}
 $files|Remove-Item -Force;Write-Host '[OK] Logs 已清除。' -ForegroundColor Green
}
function Show-FeatureGuide {
 Clear-Host
 Write-Host '========================================================' -ForegroundColor Cyan
 Write-Host ' Ragnarok 安裝管理中心：功能與腳本說明' -ForegroundColor Cyan
 Write-Host '========================================================' -ForegroundColor Cyan
 Write-Host '【選單功能】' -ForegroundColor Yellow
 Write-Host '[1] 開發環境：安裝 Git、Python、.NET、編譯工具。'
 Write-Host '[2] MariaDB：安裝或修復遊戲資料庫服務。'
 Write-Host '[3] 更新核心：從 GitHub 下載／更新 rAthena 或 PandasWS 原始碼。'
 Write-Host '[4] 編譯核心：將原始碼編譯成 login、char、map 等伺服器程式。'
 Write-Host '[5] 清除編譯：移除目前核心的舊編譯結果，不會刪除資料庫。'
 Write-Host '[6、D、E] 下載客戶端補丁、英文資源、NPC 中文化資源。'
 Write-Host '[F] 套用中文化：把已下載的資源複製到 WARP 與 rAthena。' -ForegroundColor DarkYellow
 Write-Host '[7] 建立資料庫：建立資料庫並匯入 SQL；可能寫入或覆蓋資料。' -ForegroundColor DarkYellow
 Write-Host '[8] 初始化設定：寫入 rAthena 資料庫、通訊與橋接腳本設定。' -ForegroundColor DarkYellow
 Write-Host '[I、J] 準備或開啟玩家管理後台。J 不會下載檔案。'
 Write-Host '[C、H] 啟動或停止遊戲伺服器。'
 Write-Host '[B] 全部移除：會刪除伺服器安裝內容，必須確認後才執行。' -ForegroundColor Red
 Write-Host ''
 Write-Host '【腳本模組】' -ForegroundColor Yellow
 Write-Host 'Common：共用安全檢查、命令執行與檔案複製。'
 Write-Host 'Config：讀取與儲存安裝位置、資料庫與核心設定。'
 Write-Host 'Environment：安裝／修復開發工具與 MariaDB。'
 Write-Host 'Git：下載、更新並比對 GitHub 專案版本。'
 Write-Host 'Database：建立資料庫與匯入 rAthena SQL。'
 Write-Host 'ConfigEditor：寫入 rAthena 設定及 Player Admin 橋接腳本。'
 Write-Host 'Compiler：用 Visual Studio 編譯或清除伺服器核心。'
 Write-Host 'Localization：將下載的語言資源套用到客戶端與 NPC。'
 Write-Host 'PlayerAdmin：安裝、設定並啟動網頁玩家管理後台。'
 Write-Host 'Service：啟動、停止、移除伺服器與一鍵初始化。'
 Write-Host 'Logger：寫入 Logs；UI：顯示畫面與進度。'
 Write-Host ''
 Read-Host '按 Enter 回到主選單' | Out-Null
}
