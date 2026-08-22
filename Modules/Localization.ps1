Set-StrictMode -Version 2.0
<# 中文化套用：將已下載的英文客戶端資源與繁中 NPC 腳本複製到正確位置。 #>
function Apply-RagnarokLocalization {
 param([switch]$SkipRemoteCheck)
 $c=$script:InstallerConfig;$core=Get-CoreInfo
 $updated=@()
 if(-not$SkipRemoteCheck){
  $r=$c.Repositories.ROenglishRE;if(Update-GitRepository 'ROenglishRE' $r.Url $r.Branch $c.ROenglishREPath){$updated+='ROenglishRE'}
  $r=$c.Repositories.NpcBig5;if(Update-GitRepository 'NPC 中文化' $r.Url $r.Branch $c.NpcBig5Path){$updated+='NPC 中文化'}
 }
 if(Test-Path $c.ROenglishREPath){$src=$c.ROenglishREPath;$data=Join-Path $src 'data';if(Test-Path $data){$src=$data};Copy-DirectoryContent $src (Join-Path $c.ClientPatchPath 'data');Write-Log 'ROenglishRE 已套用。' 'INFO' 'Localization.log'}else{Write-Host '[-] ROenglishRE 尚未下載。' -ForegroundColor DarkYellow}
 if(Test-Path $c.NpcBig5Path){$src=$c.NpcBig5Path;$npc=Join-Path $src 'npc';if(Test-Path $npc){$src=$npc};Copy-DirectoryContent $src (Join-Path $core.Path 'npc');Write-Log 'NPC 中文化已套用。' 'INFO' 'Localization.log'}else{Write-Host '[-] NPC 中文化尚未下載。' -ForegroundColor DarkYellow}
 $updateText=if($updated.Count){'，並已取得：'+($updated-join '、')}elseif($SkipRemoteCheck){''}else{'；遠端來源均已是最新版'}
 $script:MenuNotice=('中文化套用完成{0}。' -f $updateText.TrimEnd('。'))
 Write-Host ('[OK] {0}' -f $script:MenuNotice) -ForegroundColor Green
}
