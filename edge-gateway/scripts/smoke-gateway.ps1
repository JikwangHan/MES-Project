$ErrorActionPreference = "Stop"

Write-Host "[SMOKE] Edge Gateway 시작" -ForegroundColor Cyan

$env:MES_BASE_URL = $env:MES_BASE_URL ?? "http://localhost:4000"
$env:MES_COMPANY_ID = $env:MES_COMPANY_ID ?? "COMPANY-A"
$env:MES_ROLE = $env:MES_ROLE ?? "VIEWER"
$env:GATEWAY_PROFILE = $env:GATEWAY_PROFILE ?? "sample_modbus_tcp"
Write-Host "[INFO] MES_BASE_URL=$($env:MES_BASE_URL)"
Write-Host "[INFO] COMPANY_ID=$($env:MES_COMPANY_ID)"
Write-Host "[INFO] PROFILE=$($env:GATEWAY_PROFILE)"
