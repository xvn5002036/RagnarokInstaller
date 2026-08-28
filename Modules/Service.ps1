Set-StrictMode -Version 2.0
<# 伺服器控制：啟動、停止、移除 Ragnarok 伺服器，及執行一鍵初始化流程。 #>
function Start-RagnarokServer {
    $core=Get-CoreInfo
    $serverPath = $core.Path
    $runServerPath = Join-Path $serverPath 'runserver.bat'
    Ensure-RagnarokRuntimeDependencies
    $serverExecutables = @(
        'login-server.exe',
        'char-server.exe',
        'map-server.exe',
        'web-server.exe'
    )

    $missing = @()
    foreach ($executableName in $serverExecutables) {
        $executablePath = Join-Path $serverPath $executableName
        if (-not (Test-Path -LiteralPath $executablePath)) { $missing += $executableName }
    }
    if ($missing.Count -gt 0) {
        throw ('{0} 缺少伺服器執行檔：{1}。請先執行 [4] 編譯。' -f $core.Name,($missing -join '、'))
    }
    if($core.Name -eq 'rAthena'){
        if (-not (Test-Path -LiteralPath $runServerPath -PathType Leaf)) {throw ('找不到 rAthena 啟動腳本：{0}' -f $runServerPath)}
        Start-Process -FilePath $runServerPath -WorkingDirectory $serverPath
        Write-Host ('[OK] 已開啟：{0}' -f $runServerPath) -ForegroundColor Green
        Write-Host '[i] runserver.bat 將負責啟動並監看 login、char、map 與 web server。' -ForegroundColor Cyan
        return
    }
    # PandasWS does not provide a Windows runserver.bat. Start its four
    # compatible server programs in the required order instead.
    foreach($executableName in $serverExecutables){
        Start-Process -FilePath (Join-Path $serverPath $executableName) -WorkingDirectory $serverPath
        Start-Sleep -Milliseconds 700
    }
    Write-Host ('[OK] 已啟動 PandasWS：{0}' -f ($serverExecutables -join '、')) -ForegroundColor Green
    Write-Host '[i] PandasWS 在 Windows 下由安裝管理中心依序啟動四個伺服器程式；停止請使用 [H]。' -ForegroundColor Cyan
}
function Stop-RagnarokServer {
 foreach($processName in @('login-server','char-server','map-server','web-server')){$process=Get-Process -Name $processName -ErrorAction SilentlyContinue;if($process){$process|Stop-Process -Force;Write-Host ('[OK] 已停止 {0}。' -f $processName) -ForegroundColor Green}else{Write-Host ('[-] {0} 未執行。' -f $processName) -ForegroundColor DarkYellow}}
}
function Remove-RagnarokInstallation {
 Write-Host ('警告：即將刪除 {0} 下的伺服器、客戶端與翻譯儲存庫。MariaDB 軟體不會移除。' -f $script:InstallerConfig.RootPath) -ForegroundColor Red;$ok=Read-Host '輸入 DELETE 確認';if($ok -ne 'DELETE'){Write-Host '[-] 已取消。';return}
 foreach($p in @($script:InstallerConfig.RAthenaPath,$script:InstallerConfig.PandasWSPath,$script:InstallerConfig.ClientPatchPath,$script:InstallerConfig.ROenglishREPath,$script:InstallerConfig.NpcBig5Path,$script:InstallerConfig.PlayerAdminPath)){if(Test-Path $p){Remove-Item $p -Recurse -Force;Write-Log ('已移除：{0}' -f $p) 'INFO' 'Remove.log'}};Write-Host '[OK] 已完成安全移除。' -ForegroundColor Green
}
function Invoke-OneClickSetup {
 $steps=@('更新伺服器核心','更新 WARP','更新 ROenglishRE','更新 NPC 中文化','建立 / 匯入資料庫','初始化核心設定','清除後重新編譯','套用中文化');$board=New-StatusBoard $steps;$core=Get-CoreInfo
 Invoke-StatusStep $board '更新伺服器核心' {Update-GitRepository $core.Name $core.Repo.Url $core.Repo.Branch $core.Path}
 Invoke-StatusStep $board '更新 WARP' {Update-GitRepository 'WARP' $script:InstallerConfig.Repositories.ClientPatch.Url $script:InstallerConfig.Repositories.ClientPatch.Branch $script:InstallerConfig.ClientPatchPath}
 Invoke-StatusStep $board '更新 ROenglishRE' {Update-GitRepository 'ROenglishRE' $script:InstallerConfig.Repositories.ROenglishRE.Url $script:InstallerConfig.Repositories.ROenglishRE.Branch $script:InstallerConfig.ROenglishREPath}
 Invoke-StatusStep $board '更新 NPC 中文化' {Update-GitRepository 'NPC 中文化' $script:InstallerConfig.Repositories.NpcBig5.Url $script:InstallerConfig.Repositories.NpcBig5.Branch $script:InstallerConfig.NpcBig5Path}
 Invoke-StatusStep $board '建立 / 匯入資料庫' {Initialize-RagnarokDatabase};Invoke-StatusStep $board '初始化核心設定' {Initialize-ServerConfig};Invoke-StatusStep $board '清除後重新編譯' {Invoke-VisualStudioBuild -Target Rebuild};Invoke-StatusStep $board '套用中文化' {Apply-RagnarokLocalization -SkipRemoteCheck}
 Show-StatusBoard $board '全部完成（伺服器未自動啟動）';Write-Host '';Write-Host '[OK] 一鍵初始化完成。' -ForegroundColor Green
 Write-Host ('資料庫：{0} / {1}' -f $script:InstallerConfig.Database.MainDatabase,$script:InstallerConfig.Database.LogDatabase);Write-Host ('資料庫帳號：{0}' -f $script:InstallerConfig.Database.ServerUserName);Write-Host ('資料庫密碼：{0}' -f $script:InstallerConfig.Database.ServerPassword);Write-Host '管理員帳號：froggos1';Write-Host '管理員密碼：froggop1';Write-Host 'GM 帳號：test';Write-Host 'GM 密碼：test'
}
