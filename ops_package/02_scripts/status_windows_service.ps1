<# 
  ops_package/02_scripts/status_windows_service.ps1

  목적
  - MES Windows 서비스 상태와 로그 위치를 안내합니다.
#>

param(
  [string]$ServiceName = "MES-WebServer"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $svc) {
  Write-Host "==> 서비스가 없습니다: $ServiceName"
  return
}

Write-Host "==> 서비스 상태: $($svc.Status)"
Write-Host "==> 로그 경로: logs\\windows_service\\service_stdout.log"
Write-Host "==> 로그 경로: logs\\windows_service\\service_stderr.log"
