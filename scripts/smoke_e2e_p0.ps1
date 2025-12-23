param(
  [string]$BaseUrl = "http://localhost:4000",
  [string]$CompanyId = "COMPANY-A",
  [string]$EquipmentCode = "EQ-GW-001"
)

$ErrorActionPreference = "Stop"
$PSDefaultParameterValues["Get-Content:Encoding"] = "utf8"

function Fail([string]$Message) {
  Write-Host "[FAIL] $Message" -ForegroundColor Red
  exit 1
}

function Pass([string]$Message) {
  Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Invoke-Json {
  param(
    [string]$Method,
    [string]$Url,
    [hashtable]$Headers,
    [string]$Body = $null
  )
  try {
    if ($Body) {
      return Invoke-RestMethod -Method $Method -Headers $Headers -Uri $Url -Body $Body
    }
    return Invoke-RestMethod -Method $Method -Headers $Headers -Uri $Url
  } catch {
    $status = $_.Exception.Response.StatusCode.value__ 2>$null
    $body = ""
    try {
      $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
      $body = $reader.ReadToEnd()
    } catch { }
    Fail "$Method $Url (status=$status) $body"
  }
}

Write-Host "[INFO] E2E P0 smoke start"
Write-Host "[INFO] BASE_URL=$BaseUrl"
Write-Host "[INFO] COMPANY_ID=$CompanyId"

$headersViewer = @{
  "x-company-id" = $CompanyId
  "x-role" = "VIEWER"
}
$headersOperator = @{
  "x-company-id" = $CompanyId
  "x-role" = "OPERATOR"
}

try {
  $health = Invoke-RestMethod -Headers $headersViewer -Uri "$BaseUrl/health" -Method Get
  if (-not $health.success) {
    Fail "health check failed"
  }
} catch {
  Fail "MES server not ready (health check failed)"
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$simPath = Join-Path $repoRoot "tools\modbus-sim\server.js"
$simProfile = Join-Path $repoRoot "tools\modbus-sim\profiles\sample_modbus_tcp_sim.json"

$sim = Start-Process -FilePath "node" -ArgumentList "`"$simPath`" --profile `"$simProfile`"" -WorkingDirectory $repoRoot -PassThru
Start-Sleep -Seconds 1
Pass "E2E-P0-01 modbus sim started"

$equipList = Invoke-Json "GET" "$BaseUrl/api/v1/equipments" $headersOperator
$equip = $equipList.data | Where-Object { $_.code -eq $EquipmentCode } | Select-Object -First 1
if (-not $equip) {
  if ($sim) { Stop-Process -Id $sim.Id -Force -ErrorAction SilentlyContinue }
  Fail "equipment not found for $EquipmentCode"
}

$issue = Invoke-Json "POST" "$BaseUrl/api/v1/equipments/$($equip.id)/device-key" $headersOperator "{}"
if (-not $issue.data.deviceKeyId -or -not $issue.data.deviceSecret) {
  if ($sim) { Stop-Process -Id $sim.Id -Force -ErrorAction SilentlyContinue }
  Fail "device-key issue failed"
}

$env:MES_BASE_URL = $BaseUrl
$env:MES_COMPANY_ID = $CompanyId
$env:MES_DEVICE_KEY = $issue.data.deviceKeyId
$env:MES_DEVICE_SECRET = $issue.data.deviceSecret
$env:MES_SIGNING_ENABLED = "1"
$env:MES_CANONICAL = "stable-json"
$env:GATEWAY_PROFILE = "sample_modbus_tcp_sim"
$env:GATEWAY_RAWLOG_DIR = "$env:TEMP\gw_raw"
$env:GATEWAY_RETRY_DIR = "$env:TEMP\gw_retry"

Push-Location (Join-Path $repoRoot "edge-gateway")
try {
  node src/index.js --once
} catch {
  if ($sim) { Stop-Process -Id $sim.Id -Force -ErrorAction SilentlyContinue }
  Pop-Location
  Fail "gateway once failed"
}
Pop-Location
Pass "E2E-P0-02 gateway once completed"

Push-Location $repoRoot
try {
  pwsh -NoProfile -ExecutionPolicy Bypass -File ".\scripts\smoke_ui_p0.ps1"
} catch {
  if ($sim) { Stop-Process -Id $sim.Id -Force -ErrorAction SilentlyContinue }
  Pop-Location
  Fail "UI P0 smoke failed"
}
Pop-Location
Pass "E2E-P0-03 UI P0 smoke completed"

if ($sim) { Stop-Process -Id $sim.Id -Force -ErrorAction SilentlyContinue }

Write-Host "[PASS] E2E-P0 smoke completed" -ForegroundColor Green
