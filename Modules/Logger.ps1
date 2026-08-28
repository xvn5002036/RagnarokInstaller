Set-StrictMode -Version 2.0
<# 記錄工具：建立 Logs 資料夾，將安裝與錯誤訊息寫入記錄檔。 #>
function Initialize-LogDirectory { param([string]$Path) if(-not(Test-Path -LiteralPath $Path)){New-Item -ItemType Directory -Path $Path -Force|Out-Null} }
function Write-Log {
 param([Parameter(Mandatory=$true)][string]$Message,[ValidateSet('INFO','WARN','ERROR')][string]$Level='INFO',[string]$FileName='Install.log')
 Initialize-LogDirectory $script:LogsPath
 $line='{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message
 Add-Content -LiteralPath (Join-Path $script:LogsPath $FileName) -Value $line -Encoding UTF8
}
