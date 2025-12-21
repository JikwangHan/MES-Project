<# 
  ops_package/02_scripts/install_windows_service.ps1

  목적
  - NSSM으로 MES 서버를 Windows 서비스로 등록합니다.
  - 표준 서비스명과 로그 경로를 고정합니다.
#>

param(
  [string]$NssmPath = "C:\\tools\\nssm\\nssm.exe",
  [string]$ServiceName = "MES-WebServer",
  [string]$RepoRoot = $PWD.Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

if (-not (Test-Path $NssmPath)) {
  throw "NSSM 경로가 없습니다: $NssmPath"
}

$startScript = Join-Path $RepoRoot "ops_package\\02_scripts\\start_mes.ps1"
if (-not (Test-Path $startScript)) {
  throw "start_mes.ps1를 찾을 수 없습니다: $startScript"
}

$logDir = Join-Path $RepoRoot "logs\\windows_service"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

$app = "powershell.exe"
$args = "-NoProfile -ExecutionPolicy Bypass -File `"$startScript`""

& $NssmPath install $ServiceName $app $args
& $NssmPath set $ServiceName AppDirectory $RepoRoot
& $NssmPath set $ServiceName AppStdout (Join-Path $logDir "service_stdout.log")
& $NssmPath set $ServiceName AppStderr (Join-Path $logDir "service_stderr.log")
& $NssmPath set $ServiceName Start SERVICE_AUTO_START

Write-Host "==> 서비스 등록 완료: $ServiceName"
Write-Host "==> 시작: nssm start $ServiceName"
