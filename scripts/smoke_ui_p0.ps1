param(
  [string]$BaseUrl = "http://localhost:4000",
  [string]$CompanyId = "COMPANY-A",
  [string]$Role = "VIEWER",
  [int]$TelemetryLimit = 20
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
    [string]$Url
  )
  try {
    return Invoke-RestMethod -Method $Method -Headers $global:Headers -Uri $Url
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

$global:Headers = @{
  "x-company-id" = $CompanyId
  "x-role" = $Role
}

if ($TelemetryLimit -lt 1 -or $TelemetryLimit -gt 100) {
  Fail "TelemetryLimit must be 1..100"
}

Write-Host "[INFO] UI P0 smoke start"
Write-Host "[INFO] BASE_URL=$BaseUrl"
Write-Host "[INFO] COMPANY_ID=$CompanyId"

$equipments = Invoke-Json "GET" "$BaseUrl/api/v1/equipments"
if (-not $equipments.success) { Fail "equipments response missing success=true" }
if (-not $equipments.data) { Fail "equipments response missing data" }
if (-not ($equipments.data -is [System.Collections.IEnumerable])) { Fail "equipments data is not array" }

$first = $equipments.data | Select-Object -First 1
if (-not $first) { Fail "equipments list is empty" }
if (-not $first.PSObject.Properties.Name -contains "lastSeenAt") { Fail "equipments item missing lastSeenAt" }
if (-not $first.PSObject.Properties.Name -contains "status") { Fail "equipments item missing status" }

Pass "UI-P0-01 equipments list fields (lastSeenAt/status)"

$dashboard = Invoke-Json "GET" "$BaseUrl/api/v1/dashboard/telemetry-status"
if (-not $dashboard.success) { Fail "telemetry-status response missing success=true" }
if (-not $dashboard.data) { Fail "telemetry-status response missing data" }
if (-not $dashboard.data.counts) { Fail "telemetry-status missing counts" }
if (-not $dashboard.data.counts.PSObject.Properties.Name -contains "ok") { Fail "telemetry-status counts missing ok" }
if (-not $dashboard.data.counts.PSObject.Properties.Name -contains "warning") { Fail "telemetry-status counts missing warning" }
if (-not $dashboard.data.counts.PSObject.Properties.Name -contains "never") { Fail "telemetry-status counts missing never" }

Pass "UI-P0-02 dashboard telemetry status counts"

$telemetry = Invoke-Json "GET" "$BaseUrl/api/v1/equipments/$($first.id)/telemetry?limit=$TelemetryLimit"
if (-not $telemetry.success) { Fail "telemetry list response missing success=true" }
if (-not ($telemetry.data -is [System.Collections.IEnumerable])) { Fail "telemetry list data is not array" }

$telemetryItem = $telemetry.data | Select-Object -First 1
if ($telemetryItem) {
  if (-not $telemetryItem.PSObject.Properties.Name -contains "eventTs") { Fail "telemetry item missing eventTs" }
  if (-not $telemetryItem.PSObject.Properties.Name -contains "metricCount") { Fail "telemetry item missing metricCount" }
}

Pass "UI-P0-03 equipment telemetry list (eventTs/metricCount)"
Write-Host "[PASS] UI P0 smoke completed"
