<# 
  ops_package/02_scripts/uninstall_windows_service.ps1

  목적
  - NSSM으로 등록된 MES 서비스를 중지하고 제거합니다.
#>

param(
  [string]$NssmPath = "C:\\tools\\nssm\\nssm.exe",
  [string]$ServiceName = "MES-WebServer"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path $NssmPath)) {
  throw "NSSM 경로가 없습니다: $NssmPath"
}

try {
  Stop-Service -Name $ServiceName -ErrorAction SilentlyContinue
} catch {
}

& $NssmPath remove $ServiceName confirm
Write-Host "==> 서비스 제거 완료: $ServiceName"
