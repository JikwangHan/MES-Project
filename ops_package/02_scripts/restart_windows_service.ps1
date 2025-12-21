<# 
  ops_package/02_scripts/restart_windows_service.ps1

  목적
  - MES Windows 서비스를 재시작합니다.
#>

param(
  [string]$ServiceName = "MES-WebServer"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Restart-Service -Name $ServiceName
Write-Host "==> 서비스 재시작 완료: $ServiceName"
