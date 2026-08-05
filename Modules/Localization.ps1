Set-StrictMode -Version 2.0
function Apply-RagnarokLocalization {
 $c=$script:InstallerConfig;$core=Get-CoreInfo
 if(Test-Path $c.ROenglishREPath){$src=$c.ROenglishREPath;$data=Join-Path $src 'data';if(Test-Path $data){$src=$data};Copy-DirectoryContent $src (Join-Path $c.ClientPatchPath 'data');Write-Log 'ROenglishRE 已套用。' 'INFO' 'Localization.log'}else{Write-Host '[-] ROenglishRE 尚未下載。' -ForegroundColor DarkYellow}
 if(Test-Path $c.NpcBig5Path){$src=$c.NpcBig5Path;$npc=Join-Path $src 'npc';if(Test-Path $npc){$src=$npc};Copy-DirectoryContent $src (Join-Path $core.Path 'npc');Write-Log 'NPC 中文化已套用。' 'INFO' 'Localization.log'}else{Write-Host '[-] NPC 中文化尚未下載。' -ForegroundColor DarkYellow}
 Write-Host '[OK] 中文化套用完成。' -ForegroundColor Green;Pause-Console
}
