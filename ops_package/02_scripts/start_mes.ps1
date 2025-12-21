<# 
  ops_package/02_scripts/start_mes.ps1

  목적
  - .env 로딩 후 MES 서버를 시작합니다.
  - Windows 서비스(NSSM)에서 호출하는 표준 진입점입니다.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

# .env 로딩 (환경변수가 있으면 덮어쓰지 않음)
$dotenv = Join-Path $RepoRoot "scripts\ops\load_dotenv.ps1"
$envPath = Join-Path $RepoRoot ".env"
if (Test-Path $dotenv) {
  . $dotenv -Path $envPath
}

$logDir = Join-Path $RepoRoot "logs\windows_service"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$stdout = Join-Path $logDir "service_stdout.log"
$stderr = Join-Path $logDir "service_stderr.log"

Write-Host "==> MES 서버 시작: node src/server.js"

# stdout/stderr를 파일로 남기고 프로세스를 유지합니다.
Push-Location $RepoRoot
try {
  & node "src/server.js" 1>> $stdout 2>> $stderr
} finally {
  Pop-Location
}
