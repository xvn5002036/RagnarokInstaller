#requires -Version 5.1
[CmdletBinding()]param()
Set-StrictMode -Version 2.0;$ErrorActionPreference='Stop'
$script:AppPath=Split-Path -Parent $MyInvocation.MyCommand.Path;$script:ConfigPath=Join-Path $script:AppPath 'Config';$script:LogsPath=Join-Path $script:AppPath 'Logs';$script:ConfigFile=Join-Path $script:ConfigPath 'installer.json'
foreach($m in @('Logger.ps1','Common.ps1','UI.ps1','Config.ps1','Environment.ps1','Git.ps1','Database.ps1','ConfigEditor.ps1','Compiler.ps1','Localization.ps1','Service.ps1')){. (Join-Path (Join-Path $script:AppPath 'Modules') $m)}
try{Assert-Administrator;$script:InstallerConfig=Get-InstallerConfig;Initialize-ApplicationDirectories;Write-Log 'Ragnarok 安裝管理中心已啟動。'}catch{Write-Host ('[X] 初始化失敗：{0}' -f $_.Exception.Message) -ForegroundColor Red;exit 1}
function Show-MainMenu {
 Clear-Host;$core=Get-CoreInfo
 Write-Host '========================================================' -ForegroundColor Cyan
 Write-Host '       Ragnarok 安裝管理中心 v6.0 精裝版' -ForegroundColor Cyan
 Write-Host '========================================================' -ForegroundColor Cyan
 Write-Host ('程式位置：{0}' -f $script:AppPath) -ForegroundColor DarkGray
 Write-Host ('目前核心：{0}    安裝位置：{1}' -f $core.Name,$core.Path)
 Write-Host '';Show-CompactSystemStatus;Write-Host ''
 Write-Host '【環境管理】' -ForegroundColor Yellow
 Write-Host '[1] 安裝 / 更新開發環境';Write-Host '[2] 安裝 / 更新 MariaDB';Write-Host ''
 Write-Host '【伺服器管理】' -ForegroundColor Yellow
 Write-Host '[3] 更新 rAthena / PandasWS';Write-Host '[4] 編譯目前核心';Write-Host '[5] 清除後重新編譯目前核心';Write-Host ''
 Write-Host '【客戶端與中文化】' -ForegroundColor Yellow
 Write-Host '[6] 更新 WARP              [D] 更新 ROenglishRE';Write-Host '[E] 更新 NPC 腳本中文化    [F] 套用中文化';Write-Host ''
 Write-Host '【資料庫】' -ForegroundColor Yellow
 Write-Host '[7] 建立 / 匯入資料庫';Write-Host '[8] 初始化 rAthena 設定';Write-Host ''
 Write-Host '【工具】' -ForegroundColor Yellow
 Write-Host '[9] 顯示系統資訊           [A] 開啟 Logs';Write-Host '[L] 清除 Logs              [B] 全部移除'
 Write-Host '[C] 啟動伺服器             [H] 停止伺服器';Write-Host '[G] 一鍵初始化（不自動啟動）';Write-Host '[0] 離開'
 Write-Host '========================================================' -ForegroundColor Cyan
}
$run=$true;while($run){Show-MainMenu;$choice=Read-MenuChoice;try{switch($choice){'1'{Install-DevelopmentEnvironment}'2'{Install-MariaDBEnvironment}'3'{Update-ServerRepository}'4'{Build-RagnarokServer}'5'{Rebuild-RagnarokServer}'6'{Update-ClientPatchRepository}'7'{Initialize-RagnarokDatabase}'8'{Initialize-RAthenaConfig}'9'{Show-InstallerConfig;Pause-Console}'A'{Open-LogsFolder}'L'{Clear-InstallerLogs}'B'{Remove-RagnarokInstallation}'C'{Start-RagnarokServer}'H'{Stop-RagnarokServer}'D'{Update-ROenglishRERepository}'E'{Update-NpcBig5Repository}'F'{Apply-RagnarokLocalization}'G'{Invoke-OneClickSetup}'0'{$run=$false}default{Write-Host '[X] 無效選項。' -ForegroundColor Red;Start-Sleep 1}}}catch{Write-Host ('[X] {0}' -f $_.Exception.Message) -ForegroundColor Red;Write-Log $_.Exception.ToString() 'ERROR';Pause-Console}}
Write-Log 'Ragnarok 安裝管理中心已結束。'
