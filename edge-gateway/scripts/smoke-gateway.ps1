$ErrorActionPreference = "Stop"

Write-Host "[SMOKE] Edge Gateway 시작" -ForegroundColor Cyan

$env:MES_BASE_URL = $env:MES_BASE_URL ?? "http://localhost:4000"
$env:MES_COMPANY_ID = $env:MES_COMPANY_ID ?? "COMPANY-A"
$env:MES_ROLE = $env:MES_ROLE ?? "VIEWER"
$env:GATEWAY_PROFILE = $env:GATEWAY_PROFILE ?? "sample_modbus_tcp"
Write-Host "[INFO] MES_BASE_URL=$($env:MES_BASE_URL)"
Write-Host "[INFO] COMPANY_ID=$($env:MES_COMPANY_ID)"
Write-Host "[INFO] PROFILE=$($env:GATEWAY_PROFILE)"
Write-Host "[INFO] CANONICAL=$($env:MES_CANONICAL)"

function Invoke-GatewayOnce {
  param([string]$Label)
  Write-Host "[INFO] Run: $Label"
  node .\src\index.js --once
  if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] edge-gateway one-shot failed ($Label)" -ForegroundColor Red
    exit 1
  }
}

# One-shot run (signing OFF) - 기본은 스킵, 필요 시에만 실행
if ($env:SMOKE_GATEWAY_TEST_UNSIGNED -eq "1") {
  $env:MES_SIGNING_ENABLED = "0"
  Invoke-GatewayOnce "signing OFF"
} else {
  Write-Host "[INFO] signing OFF skipped (set SMOKE_GATEWAY_TEST_UNSIGNED=1 to enable)"
}

# Signing ON (stable-json)
if ($env:MES_DEVICE_KEY -and $env:MES_DEVICE_SECRET) {
  $env:MES_SIGNING_ENABLED = "1"
  $env:MES_CANONICAL = "stable-json"
  Invoke-GatewayOnce "signing ON (stable-json)"
} else {
  Write-Host "[FAIL] signing ON skipped (MES_DEVICE_KEY/SECRET missing)" -ForegroundColor Red
  Write-Host "       이 서버는 서명 필요(401)일 수 있습니다. MES_DEVICE_KEY/SECRET 설정 후 재실행하세요."
  exit 1
}

# Optional legacy-json compatibility test
if ($env:SMOKE_GATEWAY_TEST_LEGACY -eq "1") {
  if ($env:MES_DEVICE_KEY -and $env:MES_DEVICE_SECRET) {
    $env:MES_SIGNING_ENABLED = "1"
    $env:MES_CANONICAL = "legacy-json"
    Invoke-GatewayOnce "signing ON (legacy-json)"
  } else {
    Write-Host "[WARN] legacy-json test skipped (MES_DEVICE_KEY/SECRET missing)"
  }
}

Write-Host "[PASS] Edge Gateway smoke completed" -ForegroundColor Green
