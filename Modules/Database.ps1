Set-StrictMode -Version 2.0
function Find-MariaDbClient {
 $c=Get-Command mariadb.exe -ErrorAction SilentlyContinue; if($c){return $c.Source}; $c=Get-Command mysql.exe -ErrorAction SilentlyContinue; if($c){return $c.Source}
 $hits=Get-ChildItem 'C:\Program Files\MariaDB*\bin\mariadb.exe','C:\Program Files\MariaDB*\bin\mysql.exe' -ErrorAction SilentlyContinue|Select-Object -First 1; if($hits){return $hits.FullName}; throw '找不到 mariadb.exe / mysql.exe。'
}
function Invoke-MariaDbSql { param([string]$Sql,[string]$Database='',[string]$InputFile='')
 # PandasWS / rAthena 的 SQL 含中文與羅馬數字等 UTF-8 字元；Windows PowerShell 預設會以 ANSI
 # 管線輸出並破壞它們，最後造成 MariaDB 在看似正常的 VALUES 附近報 1064。
 $d=$script:InstallerConfig.Database; $exe=Find-MariaDbClient; $a=@('-h',$d.HostName,'-P',[string]$d.Port,'-u',$d.UserName,'--ssl=0','--default-character-set=utf8mb4'); if(-not [string]::IsNullOrEmpty($d.Password)){$a += ('-p{0}' -f $d.Password)}; if($Database){$a += $Database}
 $old=$ErrorActionPreference;$oldOutputEncoding=$OutputEncoding;$ErrorActionPreference='Continue'
 try{
  # 明確使用 UTF-8 將 SQL 送給 MariaDB，確保所有核心的資料檔都可原樣匯入。
  $OutputEncoding=[System.Text.UTF8Encoding]::new($false)
  if($InputFile){Get-Content -LiteralPath $InputFile -Raw|& $exe @a 2>&1|Tee-Object -FilePath (Join-Path $script:LogsPath 'SQL.log') -Append|ForEach-Object{Write-Host $_}} else{$Sql|& $exe @a 2>&1|Tee-Object -FilePath (Join-Path $script:LogsPath 'SQL.log') -Append|ForEach-Object{Write-Host $_}}
  $code=$LASTEXITCODE
 }finally{$OutputEncoding=$oldOutputEncoding;$ErrorActionPreference=$old}
 if($code -ne 0){throw ('MariaDB 指令失敗，錯誤碼：{0}' -f $code)}
}

function Get-MariaDbScalar {
 param([Parameter(Mandatory=$true)][string]$Sql)
 $d=$script:InstallerConfig.Database
 $exe=Find-MariaDbClient
 $arguments=@('-h',$d.HostName,'-P',[string]$d.Port,'-u',$d.UserName,'--ssl=0','--batch','--skip-column-names')
 if(-not[string]::IsNullOrEmpty($d.Password)){$arguments+=('-p{0}' -f $d.Password)}
 $arguments+=@('-e',$Sql)
 $old=$ErrorActionPreference;$ErrorActionPreference='Continue'
 try{$result=@(& $exe @arguments 2>&1);$code=$LASTEXITCODE}finally{$ErrorActionPreference=$old}
 if($code -ne 0){throw ('MariaDB 查詢失敗：{0}' -f ($result -join [Environment]::NewLine))}
 return ($result|Select-Object -First 1)
}

function Initialize-RagnarokDatabase {
 Edit-DatabaseConnection; $d=$script:InstallerConfig.Database; $core=Get-CoreInfo
 $mainName=$d.MainDatabase.Replace("'","''")
 $logName=$d.LogDatabase.Replace("'","''")
 $existingTableCount=[int](Get-MariaDbScalar ("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema IN ('{0}','{1}');" -f $mainName,$logName))
 $importBaseSql=$true
 if($existingTableCount -gt 0){
  Write-Host ''
  Write-Host ('[!] 偵測到現有資料庫，共有 {0} 個資料表。' -f $existingTableCount) -ForegroundColor Yellow
  Write-Host '[1] 保留現有資料，只更新權限與預設帳號（預設）'
  Write-Host '[2] 刪除現有資料庫後全新建立'
  $databaseMode=Read-Host '請選擇，直接 Enter 保留現有資料'
  if($databaseMode -eq '2'){
   $confirmation=Read-Host '此動作會清除 rathenadb 與 rathenalog，請輸入 REBUILD 確認'
   if($confirmation -ne 'REBUILD'){Write-Host '[-] 已取消全新重建。' -ForegroundColor DarkYellow;return}
   Write-Host '[..] 正在刪除舊資料庫並準備全新匯入...' -ForegroundColor Cyan
   Invoke-MariaDbSql ("DROP DATABASE IF EXISTS ``{0}``; DROP DATABASE IF EXISTS ``{1}``;" -f $d.MainDatabase,$d.LogDatabase)
  }else{
   $importBaseSql=$false
   Write-Host '[OK] 保留現有資料；略過所有基礎 SQL 重複匯入。' -ForegroundColor Green
  }
 }
 $sql="CREATE DATABASE IF NOT EXISTS ``$($d.MainDatabase)`` CHARACTER SET $($d.CharacterSet) COLLATE $($d.Collation); CREATE DATABASE IF NOT EXISTS ``$($d.LogDatabase)`` CHARACTER SET $($d.CharacterSet) COLLATE $($d.Collation); CREATE USER IF NOT EXISTS '$($d.ServerUserName)'@'localhost' IDENTIFIED BY '$($d.ServerPassword)'; CREATE USER IF NOT EXISTS '$($d.ServerUserName)'@'127.0.0.1' IDENTIFIED BY '$($d.ServerPassword)'; GRANT ALL PRIVILEGES ON ``$($d.MainDatabase)``.* TO '$($d.ServerUserName)'@'localhost'; GRANT ALL PRIVILEGES ON ``$($d.LogDatabase)``.* TO '$($d.ServerUserName)'@'localhost'; GRANT ALL PRIVILEGES ON ``$($d.MainDatabase)``.* TO '$($d.ServerUserName)'@'127.0.0.1'; GRANT ALL PRIVILEGES ON ``$($d.LogDatabase)``.* TO '$($d.ServerUserName)'@'127.0.0.1'; FLUSH PRIVILEGES;"
 Invoke-MariaDbSql $sql
 $sqlDir=Join-Path $core.Path 'sql-files'; if(-not(Test-Path $sqlDir)){throw ('找不到 SQL 目錄：{0}' -f $sqlDir)}
 $list=@(@('main.sql',$d.MainDatabase),@('web.sql',$d.MainDatabase),@('logs.sql',$d.LogDatabase),@('roulette_default_data.sql',$d.MainDatabase),@('item_db.sql',$d.MainDatabase),@('item_db2.sql',$d.MainDatabase),@('item_db_re.sql',$d.MainDatabase),@('item_db2_re.sql',$d.MainDatabase),@('item_db_equip.sql',$d.MainDatabase),@('item_db_etc.sql',$d.MainDatabase),@('item_db_usable.sql',$d.MainDatabase),@('item_db_re_equip.sql',$d.MainDatabase),@('item_db_re_etc.sql',$d.MainDatabase),@('item_db_re_usable.sql',$d.MainDatabase),@('mob_db.sql',$d.MainDatabase),@('mob_db2.sql',$d.MainDatabase),@('mob_db_re.sql',$d.MainDatabase),@('mob_db2_re.sql',$d.MainDatabase),@('mob_skill_db.sql',$d.MainDatabase),@('mob_skill_db2.sql',$d.MainDatabase),@('mob_skill_db_re.sql',$d.MainDatabase),@('mob_skill_db2_re.sql',$d.MainDatabase))
 if($importBaseSql){foreach($i in $list){$f=Join-Path $sqlDir $i[0];if(Test-Path $f){Write-Host ('[..] 匯入 {0}' -f $i[0]);Invoke-MariaDbSql '' $i[1] $f}else{Write-Host ('[-] 略過不存在檔案：{0}' -f $i[0]) -ForegroundColor DarkYellow}}}
 $loginTableCount=[int](Get-MariaDbScalar ("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='{0}' AND table_name='login';" -f $mainName))
 if($loginTableCount -eq 0){throw ('{0} 資料庫缺少 login 資料表，可能是先前匯入中斷。請重新執行第 7 項並選擇 [2] 全新建立。' -f $core.Name)}
 $post="UPDATE login SET userid='froggos1', user_pass='froggop1' WHERE account_id=1; INSERT INTO login (account_id,userid,user_pass,sex,email,group_id,state) VALUES (2000000,'test','123456','M','a@a.com',99,0) ON DUPLICATE KEY UPDATE userid='test',user_pass='test',group_id=99,state=0;"
 Invoke-MariaDbSql $post $d.MainDatabase
 Write-Host ('[OK] {0} 資料庫建立與匯入完成。' -f $core.Name) -ForegroundColor Green
}
