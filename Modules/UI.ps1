Set-StrictMode -Version 2.0
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
