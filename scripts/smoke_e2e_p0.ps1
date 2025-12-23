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

function FailLine([string]$Message) {
  Write-Host "[FAIL] $Message" -ForegroundColor Red
}

function Pass([string]$Message) {
  Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Skip([string]$Message) {
  Write-Host "[SKIP] $Message" -ForegroundColor Yellow
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

$mesHealthy = $false
try {
  $health = Invoke-RestMethod -Headers $headersViewer -Uri "$BaseUrl/health" -Method Get
  if ($health.success) {
    $mesHealthy = $true
    Pass "E2E-P0-00 mes health check (200 OK)"
  } else {
    FailLine "E2E-P0-00 mes health check (reason=mes_health_not_200_or_unreachable)"
  }
} catch {
  FailLine "E2E-P0-00 mes health check (reason=mes_health_not_200_or_unreachable)"
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$simPath = Join-Path $repoRoot "tools\modbus-sim\server.js"
$simProfile = Join-Path $repoRoot "tools\modbus-sim\profiles\sample_modbus_tcp_sim.json"

$sim = Start-Process -FilePath "node" -ArgumentList "`"$simPath`" --profile `"$simProfile`"" -WorkingDirectory $repoRoot -PassThru
Start-Sleep -Seconds 1
Pass "E2E-P0-01 modbus sim started"

$deviceKeyId = ""
$deviceSecret = ""
if ($mesHealthy) {
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
  $deviceKeyId = $issue.data.deviceKeyId
  $deviceSecret = $issue.data.deviceSecret
}

$env:MES_BASE_URL = $BaseUrl
$env:MES_COMPANY_ID = $CompanyId
$env:MES_DEVICE_KEY = $deviceKeyId
$env:MES_DEVICE_SECRET = $deviceSecret
if ($mesHealthy) {
  $env:MES_SIGNING_ENABLED = "1"
} else {
  $env:MES_SIGNING_ENABLED = "0"
}
$env:MES_CANONICAL = "stable-json"
$env:GATEWAY_PROFILE = "sample_modbus_tcp_sim"
$env:GATEWAY_RAWLOG_DIR = "$env:TEMP\gw_raw"
$env:GATEWAY_RETRY_DIR = "$env:TEMP\gw_retry"

$metricCount = "?"
try {
  $profilePath = Join-Path $repoRoot "edge-gateway\config\$($env:GATEWAY_PROFILE).json"
  if (Test-Path $profilePath) {
    $profile = Get-Content -Path $profilePath -Raw | ConvertFrom-Json
    if ($profile.metrics) {
      $metricCount = @($profile.metrics).Count
    } elseif ($profile.registerMapFile) {
      $mapPath = Join-Path (Split-Path $profilePath -Parent) $profile.registerMapFile
      if (Test-Path $mapPath) {
        $map = Get-Content -Path $mapPath -Raw | ConvertFrom-Json
        $metricCount = @($map.points).Count
      }
    }
  }
} catch { }

Push-Location (Join-Path $repoRoot "edge-gateway")
$prevErrorAction = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$gwOutput = & node src/index.js --once 2>&1
$gwExit = $LASTEXITCODE
$ErrorActionPreference = $prevErrorAction
$gwText = ""
if ($gwOutput) {
  $gwText = $gwOutput -join "`n"
  $gwOutput | ForEach-Object { Write-Host $_ }
}
Pop-Location

$normalizeOk = $gwText -match '\[PASS\] Ticket-17\.3-03 normalize payload'
if (-not $normalizeOk) {
  if ($sim) { Stop-Process -Id $sim.Id -Force -ErrorAction SilentlyContinue }
  Fail "E2E-P0-02 gateway read+normalize failed"
}
Pass "E2E-P0-02 gateway read+normalize ok (profile=$($env:GATEWAY_PROFILE) metrics=$metricCount)"

if ($gwExit -ne 0 -and $mesHealthy) {
  if ($sim) { Stop-Process -Id $sim.Id -Force -ErrorAction SilentlyContinue }
  Fail "gateway once failed"
}

$uplinkOk = $gwText -match '\[PASS\] Ticket-17\.3-04 uplink'
if ($mesHealthy) {
  if (-not $uplinkOk) {
    if ($sim) { Stop-Process -Id $sim.Id -Force -ErrorAction SilentlyContinue }
    Fail "E2E-P0-04 uplink failed (reason=fetch_failed_or_non_201)"
  }
  $uplinkStatus = [regex]::Match($gwText, '\[gateway\] uplink ok\s+(\d+)').Groups[1].Value
  if ($uplinkStatus -ne "201") {
    if ($sim) { Stop-Process -Id $sim.Id -Force -ErrorAction SilentlyContinue }
    Fail "E2E-P0-04 uplink failed (reason=status_$uplinkStatus)"
  }
  Pass "E2E-P0-04 uplink ok (status=201)"
} else {
  Skip "E2E-P0-04 uplink skipped (reason=mes_health_not_200)"
}

Push-Location $repoRoot
if ($mesHealthy) {
  try {
    pwsh -NoProfile -ExecutionPolicy Bypass -File ".\scripts\smoke_ui_p0.ps1"
  } catch {
    if ($sim) { Stop-Process -Id $sim.Id -Force -ErrorAction SilentlyContinue }
    Pop-Location
    Fail "UI P0 smoke failed"
  }
  Pass "E2E-P0-05 ui-p0 smoke ok (equipments, dashboard, telemetry)"
} else {
  Skip "E2E-P0-05 ui-p0 smoke skipped (reason=mes_down)"
}
Pop-Location

if ($sim) { Stop-Process -Id $sim.Id -Force -ErrorAction SilentlyContinue }

if (-not $mesHealthy) {
  Write-Host "[INFO] E2E-P0 smoke completed (mes_down)" -ForegroundColor Yellow
  $global:LASTEXITCODE = 2
  [Environment]::Exit(2)
}

Write-Host "[INFO] E2E-P0 smoke completed" -ForegroundColor Green
