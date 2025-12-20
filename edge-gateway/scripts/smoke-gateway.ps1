$ErrorActionPreference = "Stop"
$PSDefaultParameterValues["Get-Content:Encoding"] = "utf8"

Write-Host "[SMOKE] Edge Gateway 시작" -ForegroundColor Cyan

if (-not $env:MES_BASE_URL) { $env:MES_BASE_URL = "http://localhost:4000" }
if (-not $env:MES_COMPANY_ID) { $env:MES_COMPANY_ID = "COMPANY-A" }
if (-not $env:MES_ROLE) { $env:MES_ROLE = "VIEWER" }
if (-not $env:GATEWAY_PROFILE) { $env:GATEWAY_PROFILE = "sample_modbus_tcp" }
Write-Host "[INFO] MES_BASE_URL=$($env:MES_BASE_URL)"
Write-Host "[INFO] COMPANY_ID=$($env:MES_COMPANY_ID)"
Write-Host "[INFO] PROFILE=$($env:GATEWAY_PROFILE)"
Write-Host "[INFO] CANONICAL=$($env:MES_CANONICAL)"

$gatewayRoot = Split-Path -Parent $PSScriptRoot
$allowUnsignedOnly = ($env:SMOKE_GATEWAY_ALLOW_UNSIGNED_ONLY -eq "1")
$autoIssueKey = ($env:SMOKE_GATEWAY_AUTO_KEY -eq "1")

function Invoke-GatewayOnce {
  param([string]$Label)
  Write-Host "[INFO] Run: $Label"
  Push-Location $gatewayRoot
  try {
    node .\src\index.js --once
    if ($LASTEXITCODE -ne 0) {
      Write-Host "[FAIL] edge-gateway one-shot failed ($Label)" -ForegroundColor Red
      exit 1
    }
  } finally {
    Pop-Location
  }
}

function Invoke-CurlJson {
  param(
    [string]$Method,
    [string]$Url,
    [hashtable]$Headers,
    [string]$Body = $null
  )
  $respPath = New-TemporaryFile
  $args = @('-s', '-o', $respPath, '-w', '%{http_code}', '-X', $Method, '--url', $Url)
  foreach ($k in $Headers.Keys) {
    $args += @('-H', "$($k): $($Headers[$k])")
  }
  if ($null -ne $Body -and $Body -ne "") {
    $args += @('--data', $Body)
  }
  $status = & curl.exe @args
  $raw = ''
  if (Test-Path $respPath) {
    $raw = Get-Content $respPath -Raw
    Remove-Item $respPath -Force -ErrorAction SilentlyContinue
  }
  $json = $null
  if ($raw) {
    try { $json = $raw | ConvertFrom-Json } catch { }
  }
  return @{ Status = $status; Raw = $raw; Json = $json }
}

function Ensure-DeviceKey {
  if ($env:MES_DEVICE_KEY -and $env:MES_DEVICE_SECRET) {
    return
  }
  if (-not $autoIssueKey) {
    return
  }

  $headers = @{
    "x-company-id" = $env:MES_COMPANY_ID
    "x-role" = "OPERATOR"
  }

  $list = Invoke-CurlJson "GET" "$($env:MES_BASE_URL)/api/v1/equipments" $headers
  if ($list.Status -ne "200") {
    Write-Host "[FAIL] equipment list failed ($($list.Status))" -ForegroundColor Red
    exit 1
  }
  $equip = $list.Json.data | Where-Object { $_.code -eq $env:GATEWAY_PROFILE_EQUIPMENT_CODE } | Select-Object -First 1
  if (-not $equip) {
    Write-Host "[FAIL] equipment not found for code $($env:GATEWAY_PROFILE_EQUIPMENT_CODE)" -ForegroundColor Red
    exit 1
  }

  $issue = Invoke-CurlJson "POST" "$($env:MES_BASE_URL)/api/v1/equipments/$($equip.id)/device-key" $headers "{}"
  if ($issue.Status -ne "201" -and $issue.Status -ne "200") {
    Write-Host "[FAIL] device-key issue failed ($($issue.Status))" -ForegroundColor Red
    exit 1
  }
  $env:MES_DEVICE_KEY = $issue.Json.data.deviceKeyId
  $env:MES_DEVICE_SECRET = $issue.Json.data.deviceSecret
  Write-Host "[INFO] device-key issued for gateway equipment"
}

# One-shot run (signing OFF) - 기본은 스킵, 필요 시에만 실행
if ($env:SMOKE_GATEWAY_TEST_UNSIGNED -eq "1") {
  $env:MES_SIGNING_ENABLED = "0"
  Invoke-GatewayOnce "signing OFF"
} else {
  Write-Host "[INFO] signing OFF skipped (set SMOKE_GATEWAY_TEST_UNSIGNED=1 to enable)"
}

# Signing ON (stable-json)
if ($autoIssueKey) {
  if (-not $env:GATEWAY_PROFILE_EQUIPMENT_CODE) { $env:GATEWAY_PROFILE_EQUIPMENT_CODE = "EQ-GW-001" }
  Ensure-DeviceKey
}
if ($env:MES_DEVICE_KEY -and $env:MES_DEVICE_SECRET) {
  $env:MES_SIGNING_ENABLED = "1"
  $env:MES_CANONICAL = "stable-json"
  Invoke-GatewayOnce "signing ON (stable-json)"
} else {
  if ($allowUnsignedOnly) {
    Write-Host "[WARN] signing ON skipped (MES_DEVICE_KEY/SECRET missing)" -ForegroundColor Yellow
    Write-Host "       SMOKE_GATEWAY_ALLOW_UNSIGNED_ONLY=1 설정으로 서명 ON 단계를 건너뜁니다."
  } else {
    Write-Host "[FAIL] signing ON skipped (MES_DEVICE_KEY/SECRET missing)" -ForegroundColor Red
    Write-Host "       이 서버는 서명 필요(401)일 수 있습니다. MES_DEVICE_KEY/SECRET 설정 후 재실행하세요."
    exit 1
  }
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
