Set-StrictMode -Version 2.0
function Set-ConfValues { param([string]$FilePath,[System.Collections.IDictionary]$Values)
 if(-not(Test-Path $FilePath)){[IO.File]::WriteAllText($FilePath,'',(New-Object Text.UTF8Encoding($false)))}
 $text=[IO.File]::ReadAllText($FilePath,[Text.Encoding]::UTF8); if($null -eq $text){$text=''}
 foreach($key in $Values.Keys){$value=[string]$Values[$key];$pat='(?m)^\s*'+[regex]::Escape([string]$key)+'\s*:\s*.*$';$line=('{0}: {1}' -f $key,$value);if([regex]::IsMatch($text,$pat)){$text=[regex]::Replace($text,$pat,$line)}else{if($text.Length -gt 0 -and -not $text.EndsWith("`n")){$text+="`r`n"};$text+=$line+"`r`n"}}
 [IO.File]::WriteAllText($FilePath,$text,(New-Object Text.UTF8Encoding($false)))
}

function Convert-RAthenaImportFilesToUtf8NoBom {
 param([Parameter(Mandatory=$true)][string]$ImportPath)
 $encoding=New-Object Text.UTF8Encoding($false)
 foreach($file in Get-ChildItem -LiteralPath $ImportPath -Filter '*.txt' -File -Recurse -ErrorAction Stop){
  $content=[IO.File]::ReadAllText($file.FullName,[Text.Encoding]::UTF8)
  [IO.File]::WriteAllText($file.FullName,$content,$encoding)
 }
}

function Assert-RAthenaImportReference {
 param([string]$FilePath,[string]$ImportPath)
 if(-not(Test-Path -LiteralPath $FilePath)){throw ('找不到 rAthena 主設定檔：{0}' -f $FilePath)}
 $content=[IO.File]::ReadAllText($FilePath,[Text.Encoding]::UTF8)
 $pattern='(?im)^\s*import\s*:\s*'+[regex]::Escape($ImportPath)+'\s*$'
 if(-not[regex]::IsMatch($content,$pattern)){throw ('{0} 沒有載入 {1}' -f $FilePath,$ImportPath)}
}

function Assert-RAthenaConfValue {
 param([string]$FilePath,[string]$Key,[string]$ExpectedValue)
 $content=[IO.File]::ReadAllText($FilePath,[Text.Encoding]::UTF8)
 $pattern='(?m)^\s*'+[regex]::Escape($Key)+'\s*:\s*'+[regex]::Escape($ExpectedValue)+'\s*$'
 if(-not[regex]::IsMatch($content,$pattern)){throw ('設定驗證失敗：{0} 的 {1} 不是 {2}' -f $FilePath,$Key,$ExpectedValue)}
}

function Install-DotNetAdminBridge {
 param([Parameter(Mandatory=$true)][string]$BasePath)
 $encoding=New-Object Text.UTF8Encoding($false)
 $customDirectory=Join-Path $BasePath 'npc\custom'
 if(-not(Test-Path -LiteralPath $customDirectory)){New-Item -ItemType Directory -Path $customDirectory -Force|Out-Null}
 $bridgePath=Join-Path $customDirectory 'dotnet_admin_kick.txt'
 $bridge=@'
// Internal bridge used by tools/RathenaPlayerAdmin.
// It safely disconnects one online character without touching the map-server console.
-	script	dotnet_admin_kick	-1,{
OnInit:
	query_sql("CREATE TABLE IF NOT EXISTS `dotnet_admin_kick_queue` (`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, `char_id` INT UNSIGNED NOT NULL, `requested_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, `processed_at` DATETIME NULL, PRIMARY KEY (`id`), KEY `pending` (`processed_at`,`id`)) ENGINE=InnoDB");
	// Do not execute requests left behind by an earlier server shutdown.
	query_sql("UPDATE `dotnet_admin_kick_queue` SET `processed_at`=NOW() WHERE `processed_at` IS NULL");
	initnpctimer;
	end;

OnTimer500:
	.@count = query_sql("SELECT `id`,`char_id` FROM `dotnet_admin_kick_queue` WHERE `processed_at` IS NULL ORDER BY `id` LIMIT 20", .@request_id, .@char_id);
	for (.@i = 0; .@i < .@count; ++.@i) {
		query_sql("UPDATE `dotnet_admin_kick_queue` SET `processed_at`=NOW() WHERE `id`=" + .@request_id[.@i]);
		kick .@char_id[.@i];
	}
	query_sql("DELETE FROM `dotnet_admin_kick_queue` WHERE `processed_at` < NOW() - INTERVAL 1 DAY");
	initnpctimer;
	end;
}

// Runs the native jobchange script command on an online target character.
// This follows the same map-server path as @jobchange without requiring the
// target account to have GM permissions.
-	script	dotnet_admin_jobchange	-1,{
OnInit:
	query_sql("CREATE TABLE IF NOT EXISTS `dotnet_admin_jobchange_queue` (`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, `account_id` INT UNSIGNED NOT NULL, `char_id` INT UNSIGNED NOT NULL, `job_id` INT NOT NULL, `requested_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, `processed_at` DATETIME NULL, PRIMARY KEY (`id`), KEY `pending` (`processed_at`,`id`)) ENGINE=InnoDB");
	query_sql("UPDATE `dotnet_admin_jobchange_queue` SET `processed_at`=NOW() WHERE `processed_at` IS NULL");
	initnpctimer;
	end;

OnTimer500:
	.@count = query_sql("SELECT `id`,`account_id`,`char_id`,`job_id` FROM `dotnet_admin_jobchange_queue` WHERE `processed_at` IS NULL ORDER BY `id` LIMIT 20", .@request_id, .@account_id, .@char_id, .@job_id);
	for (.@i = 0; .@i < .@count; ++.@i) {
		// Use the script command's explicit char_id argument. attachrid(account_id)
		// can attach a different online character from the same account, making the
		// requested character appear unchanged (usually still a novice).
		if (isloggedin(.@account_id[.@i], .@char_id[.@i]) && attachrid(.@account_id[.@i])) {
			if (getcharid(0) == .@char_id[.@i]) {
				.@old_class = Class;
				jobchange .@job_id[.@i], -1, .@char_id[.@i];
				// Only fill the new skill tree after pc_jobchange actually changed Class.
				// Raise Job Level first so rAthena keeps the maxed skill tree after
				// a skill-tree reload. @joblvl clamps oversized values to the class max.
				if (Class != .@old_class) {
					atcommand "@joblvl 1000";
					atcommand "@skillall";
					// @skillall updates map-server memory but does not call chrif_save.
					// @save persists the learned skills immediately instead of waiting
					// for a later autosave or logout.
					atcommand "@save";
				}
			}
			detachrid;
		}
		query_sql("UPDATE `dotnet_admin_jobchange_queue` SET `processed_at`=NOW() WHERE `id`=" + .@request_id[.@i]);
	}
	query_sql("DELETE FROM `dotnet_admin_jobchange_queue` WHERE `processed_at` < NOW() - INTERVAL 1 DAY");
	initnpctimer;
	end;
}

// Executes a documented @command as an online GM account so output is shown in-game.
-	script	dotnet_admin_atcommand	-1,{
OnInit:
	query_sql("CREATE TABLE IF NOT EXISTS `dotnet_admin_atcommand_queue` (`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT, `account_id` INT UNSIGNED NOT NULL, `char_id` INT UNSIGNED NOT NULL, `command` VARCHAR(500) NOT NULL, `requested_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, `processed_at` DATETIME NULL, PRIMARY KEY (`id`), KEY `pending` (`processed_at`,`id`)) ENGINE=InnoDB");
	query_sql("UPDATE `dotnet_admin_atcommand_queue` SET `processed_at`=NOW() WHERE `processed_at` IS NULL");
	initnpctimer;
	end;

OnTimer500:
	.@count = query_sql("SELECT `id`,`account_id`,`command` FROM `dotnet_admin_atcommand_queue` WHERE `processed_at` IS NULL ORDER BY `id` LIMIT 20", .@request_id, .@account_id, .@command$);
	for (.@i = 0; .@i < .@count; ++.@i) {
		query_sql("UPDATE `dotnet_admin_atcommand_queue` SET `processed_at`=NOW() WHERE `id`=" + .@request_id[.@i]);
		if (attachrid(.@account_id[.@i])) {
			atcommand .@command$[.@i];
			detachrid;
		}
	}
	query_sql("DELETE FROM `dotnet_admin_atcommand_queue` WHERE `processed_at` < NOW() - INTERVAL 1 DAY");
	initnpctimer;
	end;
}
'@
 [IO.File]::WriteAllText($bridgePath,($bridge.TrimStart("`r","`n")+"`r`n"),$encoding)

 $scriptsCustomPath=Join-Path $BasePath 'npc\scripts_custom.conf'
 if(-not(Test-Path -LiteralPath $scriptsCustomPath)){throw ('找不到 NPC 自訂腳本清單：{0}' -f $scriptsCustomPath)}
 $scriptsCustom=[IO.File]::ReadAllText($scriptsCustomPath,[Text.Encoding]::UTF8)
 $includePattern='(?im)^\s*npc\s*:\s*npc/custom/dotnet_admin_kick\.txt\s*$'
 $scriptsCustom=[regex]::Replace($scriptsCustom,$includePattern,'')
 $scriptsCustom=$scriptsCustom.TrimEnd()+"`r`n`r`nnpc: npc/custom/dotnet_admin_kick.txt`r`n"
 [IO.File]::WriteAllText($scriptsCustomPath,$scriptsCustom,$encoding)

 if(-not[regex]::IsMatch([IO.File]::ReadAllText($scriptsCustomPath,[Text.Encoding]::UTF8),$includePattern)){throw 'scripts_custom.conf 未成功加入 dotnet_admin_kick.txt。'}
 $writtenBridge=[IO.File]::ReadAllText($bridgePath,[Text.Encoding]::UTF8)
 if($writtenBridge -notmatch 'dotnet_admin_kick_queue' -or $writtenBridge -notmatch 'dotnet_admin_jobchange_queue' -or $writtenBridge -notmatch 'dotnet_admin_atcommand_queue'){throw 'dotnet_admin_kick.txt 內容驗證失敗。'}
 if($writtenBridge -notmatch 'isloggedin\(\.@account_id\[\.@i\], \.@char_id\[\.@i\]\)' -or $writtenBridge -notmatch 'jobchange \.@job_id\[\.@i\], -1, \.@char_id\[\.@i\]'){throw 'dotnet_admin_kick.txt 未使用指定角色的 char_id 執行轉職。'}
 if($writtenBridge -notmatch 'if \(Class != \.@old_class\)' -or $writtenBridge -notmatch 'atcommand "@joblvl 1000"' -or $writtenBridge -notmatch 'atcommand "@skillall"' -or $writtenBridge -notmatch 'atcommand "@save"'){throw 'dotnet_admin_kick.txt 未在轉職成功後提升 Job Level、補滿技能並立即保存。'}
 Write-Host '[OK] RathenaPlayerAdmin NPC bridge 已建立並加入 scripts_custom.conf。' -ForegroundColor Green
}

function Initialize-RAthenaConfig {
 Edit-DatabaseConnection; $core=Get-CoreInfo; $base=$core.Path; if(-not(Test-Path $base)){throw ('核心目錄不存在：{0}' -f $base)}
 $tmpl=Join-Path $base 'conf\import-tmpl';$imp=Join-Path $base 'conf\import';if(-not(Test-Path $tmpl)){throw ('找不到：{0}' -f $tmpl)}
 if(-not(Test-Path $imp)){
  Copy-Item $tmpl $imp -Recurse -Force
  Write-Host '[OK] 已從 import-tmpl 完整建立 conf\import。' -ForegroundColor Green
 }else{
  foreach($sourceFile in Get-ChildItem -LiteralPath $tmpl -File -Recurse){
   $relativePath=$sourceFile.FullName.Substring($tmpl.Length).TrimStart('\')
   $targetFile=Join-Path $imp $relativePath
   if(-not(Test-Path -LiteralPath $targetFile)){
    $targetDirectory=Split-Path -Parent $targetFile
    if(-not(Test-Path -LiteralPath $targetDirectory)){New-Item -ItemType Directory -Path $targetDirectory -Force|Out-Null}
    Copy-Item -LiteralPath $sourceFile.FullName -Destination $targetFile -Force
   }
  }
  Write-Host '[OK] conf\import 已存在，只補上缺少的範本檔案。' -ForegroundColor Green
 }
 $packet=Join-Path $base 'src\config\packets.hpp'
 if(-not(Test-Path $packet)){throw ('找不到 PACKETVER 設定檔：{0}' -f $packet)}
 $packetText=[IO.File]::ReadAllText($packet,[Text.Encoding]::UTF8)
 $packetPattern='(?m)^\s*#define\s+PACKETVER\s+\d+'
 if(-not[regex]::IsMatch($packetText,$packetPattern)){throw 'packets.hpp 找不到 #define PACKETVER。'}
 $packetReplacement='#define PACKETVER {0}' -f $script:InstallerConfig.PacketVersion
 $updatedPacketText=[regex]::Replace($packetText,$packetPattern,$packetReplacement)
 if($updatedPacketText -ne $packetText){
  [IO.File]::WriteAllText($packet,$updatedPacketText,(New-Object Text.UTF8Encoding($true)))
  Write-Host ('[OK] packets.hpp 的 PACKETVER 已修改為 {0}。' -f $script:InstallerConfig.PacketVersion) -ForegroundColor Green
 }else{
  Write-Host ('[OK] packets.hpp 的 PACKETVER 已是 {0}，不需重寫。' -f $script:InstallerConfig.PacketVersion) -ForegroundColor Green
 }
 $d=$script:InstallerConfig.Database
 $inter=[ordered]@{login_server_ip=$d.HostName;login_server_port=$d.Port;login_server_id=$d.ServerUserName;login_server_pw=$d.ServerPassword;login_server_db=$d.MainDatabase;ipban_db_ip=$d.HostName;ipban_db_port=$d.Port;ipban_db_id=$d.ServerUserName;ipban_db_pw=$d.ServerPassword;ipban_db_db=$d.MainDatabase;char_server_ip=$d.HostName;char_server_port=$d.Port;char_server_id=$d.ServerUserName;char_server_pw=$d.ServerPassword;char_server_db=$d.MainDatabase;map_server_ip=$d.HostName;map_server_port=$d.Port;map_server_id=$d.ServerUserName;map_server_pw=$d.ServerPassword;map_server_db=$d.MainDatabase;web_server_ip=$d.HostName;web_server_port=$d.Port;web_server_id=$d.ServerUserName;web_server_pw=$d.ServerPassword;web_server_db=$d.WebDatabase;log_db_ip=$d.HostName;log_db_port=$d.Port;log_db_id=$d.ServerUserName;log_db_pw=$d.ServerPassword;log_db_db=$d.LogDatabase}
 Set-ConfValues (Join-Path $imp 'inter_conf.txt') $inter; Set-ConfValues (Join-Path $imp 'map_conf.txt') ([ordered]@{userid='froggos1';passwd='froggop1';console='on'}); Set-ConfValues (Join-Path $imp 'char_conf.txt') ([ordered]@{userid='froggos1';passwd='froggop1';char_del_delay='0';pincode_enabled='no';char_moves_unlimited='yes'}); Set-ConfValues (Join-Path $imp 'login_conf.txt') ([ordered]@{new_acc_length_limit='no'})
 Convert-RAthenaImportFilesToUtf8NoBom $imp
 Install-DotNetAdminBridge $base

 Assert-RAthenaImportReference (Join-Path $base 'conf\inter_athena.conf') 'conf/import/inter_conf.txt'
 Assert-RAthenaImportReference (Join-Path $base 'conf\char_athena.conf') 'conf/import/char_conf.txt'
 Assert-RAthenaImportReference (Join-Path $base 'conf\map_athena.conf') 'conf/import/map_conf.txt'
 Assert-RAthenaImportReference (Join-Path $base 'conf\login_athena.conf') 'conf/import/login_conf.txt'
 Assert-RAthenaConfValue (Join-Path $imp 'inter_conf.txt') 'login_server_id' $d.ServerUserName
 Assert-RAthenaConfValue (Join-Path $imp 'inter_conf.txt') 'log_db_db' $d.LogDatabase
 Assert-RAthenaConfValue (Join-Path $imp 'char_conf.txt') 'userid' 'froggos1'
 Assert-RAthenaConfValue (Join-Path $imp 'char_conf.txt') 'passwd' 'froggop1'
 Assert-RAthenaConfValue (Join-Path $imp 'map_conf.txt') 'userid' 'froggos1'
 Assert-RAthenaConfValue (Join-Path $imp 'map_conf.txt') 'passwd' 'froggop1'
 Assert-RAthenaConfValue (Join-Path $imp 'map_conf.txt') 'console' 'on'

 $mainName=$d.MainDatabase.Replace("'","''")
 $loginTableCount=[int](Get-MariaDbScalar ("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='{0}' AND table_name='login';" -f $mainName))
 if($loginTableCount -eq 0){throw '資料庫缺少 login 資料表，請先執行第 7 項建立 / 匯入資料庫。'}
 Invoke-MariaDbSql "UPDATE login SET userid='froggos1',user_pass='froggop1',sex='S',state=0 WHERE account_id=1;" $d.MainDatabase
 $communicationAccount=Get-MariaDbScalar ("SELECT CONCAT(userid,'|',user_pass,'|',sex) FROM ``{0}``.login WHERE account_id=1;" -f $d.MainDatabase)
 if($communicationAccount -ne 'froggos1|froggop1|S'){throw ('伺服器通訊帳號驗證失敗：{0}' -f $communicationAccount)}

 Write-Host '[OK] UTF-8 BOM 已清除，rAthena 能正確讀取第一行設定。' -ForegroundColor Green
 Write-Host '[OK] 資料庫連線、伺服器通訊帳號及 import 載入設定全部驗證完成。' -ForegroundColor Green
 if(Get-Process -Name 'login-server','char-server','map-server','web-server' -ErrorAction SilentlyContinue){Write-Host '[!] 偵測到伺服器正在執行；請先選 [H] 停止，再選 [C] 重新啟動以載入新設定。' -ForegroundColor Yellow}else{Write-Host '[i] 設定會在下次選擇 [C] 啟動伺服器時生效。' -ForegroundColor Cyan}
 Write-Host '[i] PACKETVER 屬於編譯設定；若本次有變更，請先執行 [5] 清除，再執行 [4] 編譯。' -ForegroundColor Cyan
}
