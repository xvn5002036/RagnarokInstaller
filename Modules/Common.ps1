Set-StrictMode -Version 2.0
function Test-IsAdministrator { $p=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent()); return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
function Assert-Administrator { if(-not(Test-IsAdministrator)){throw '請以系統管理員身分執行 Start.cmd。'} }
function Initialize-ApplicationDirectories { foreach($p in @($script:ConfigPath,$script:LogsPath,$script:InstallerConfig.RootPath)){if($p -and -not(Test-Path -LiteralPath $p)){New-Item -ItemType Directory -Path $p -Force|Out-Null}} }
function Read-MenuChoice { param([string]$Prompt='請選擇'); return (Read-Host $Prompt).Trim().ToUpperInvariant() }
function Pause-Console { Write-Host ''; [void](Read-Host '按 Enter 返回主選單') }
function Open-LogsFolder { Initialize-LogDirectory $script:LogsPath; Start-Process explorer.exe -ArgumentList ('"{0}"' -f $script:LogsPath) }
function Test-Command { param([string]$Name); return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue) }
function Get-MariaDbService {
 $services=Get-CimInstance Win32_Service -ErrorAction SilentlyContinue|Where-Object {
  $_.Name -match 'MariaDB|MySQL' -or $_.DisplayName -match 'MariaDB|MySQL' -or ($_.PathName -match 'mysqld\.exe' -and $_.PathName -match 'MariaDB')
 }
 if($services){return @($services|Sort-Object @{Expression={if($_.State -eq 'Running'){0}else{1}}},Name)[0]}
 return $null
}
function Invoke-Native {
 param([Parameter(Mandatory=$true)][string]$FilePath,[string[]]$Arguments=@(),[string]$WorkingDirectory='',[string]$LogFile='Install.log',[switch]$AllowFailure)
 $old=$ErrorActionPreference; $ErrorActionPreference='Continue'
 try {
  if($WorkingDirectory){Push-Location $WorkingDirectory}
  Write-Log -Message ('執行：{0} {1}' -f $FilePath,($Arguments -join ' ')) -FileName $LogFile
  & $FilePath @Arguments 2>&1 | Tee-Object -FilePath (Join-Path $script:LogsPath $LogFile) -Append | ForEach-Object { Write-Host $_ }
  $code=$LASTEXITCODE
 } finally { if($WorkingDirectory){Pop-Location}; $ErrorActionPreference=$old }
 if($code -ne 0 -and -not $AllowFailure){throw ('外部程式失敗（錯誤碼 {0}）：{1}' -f $code,$FilePath)}
 return $code
}
function Copy-DirectoryContent {
 param([string]$Source,[string]$Destination,[string[]]$Exclude=@('.git','.github'))
 if(-not(Test-Path $Source)){throw ('來源不存在：{0}' -f $Source)}
 if(-not(Test-Path $Destination)){New-Item -ItemType Directory -Path $Destination -Force|Out-Null}
 $args=@($Source,$Destination,'/E','/R:2','/W:2','/NFL','/NDL','/NJH','/NJS','/NP')
 foreach($x in $Exclude){$args += @('/XD',(Join-Path $Source $x))}
 $code=Invoke-Native -FilePath 'robocopy.exe' -Arguments $args -LogFile 'Install.log' -AllowFailure
 if($code -ge 8){throw ('Robocopy 失敗，錯誤碼：{0}' -f $code)}
}
function Read-WithDefault { param([string]$Prompt,[string]$Default); $v=Read-Host ('{0}（目前 {1}）' -f $Prompt,$Default); if([string]::IsNullOrWhiteSpace($v)){return $Default}; return $v }
