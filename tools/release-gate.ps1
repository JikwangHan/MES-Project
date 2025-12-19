<#
설명
- 릴리즈 게이트를 원클릭으로 실행합니다.
- 순서: develop 최신화 -> 서버 헬스 확인 -> smoke 실행 -> (옵션) ERD 게이트 -> 태그 계산/생성/푸시
- (옵션) main 병합 및 main smoke까지 수행할 수 있습니다.

사용 예시
- DryRun(태그 계산만):
  pwsh .\tools\release-gate.ps1
- 태그 생성 + 푸시:
  pwsh .\tools\release-gate.ps1 -ApplyTag -PushTag
- ERD Mermaid까지:
  pwsh .\tools\release-gate.ps1 -ApplyTag -PushTag -ErdMermaid -ErdEnforce
- main 병합 + main smoke:
  pwsh .\tools\release-gate.ps1 -ApplyTag -PushTag -MergeMain -SmokeOnMain
#>

[CmdletBinding()]
param(
  [string]$Branch = "develop",
  [string]$Remote = "origin",
  [string]$BaseUrl = "http://localhost:4000",
  [string]$HealthUrl = "",
  [string]$Series = "",
  [switch]$ApplyTag,
  [switch]$PushTag,
  [switch]$MergeMain,
  [switch]$SmokeOnMain,
  [switch]$ErdMermaid,
  [switch]$ErdRender,
  [switch]$ErdStrict,
  [switch]$ErdEnforce,
  [switch]$ProbeGateway
)

$ErrorActionPreference = "Stop"

# Ticket-14.1 운영 룰 기본값
if (-not $env:REPORT_KPI_CACHE_MODE -or [string]::IsNullOrWhiteSpace($env:REPORT_KPI_CACHE_MODE)) {
  $env:REPORT_KPI_CACHE_MODE = "PREFER"
}
if (-not $env:RELEASE_GATE_REPORT_CACHE_PROBE -or [string]::IsNullOrWhiteSpace($env:RELEASE_GATE_REPORT_CACHE_PROBE)) {
  $env:RELEASE_GATE_REPORT_CACHE_PROBE = "1"
}
if (-not $env:RELEASE_GATE_REPORT_CACHE_STRICT -or [string]::IsNullOrWhiteSpace($env:RELEASE_GATE_REPORT_CACHE_STRICT)) {
  $env:RELEASE_GATE_REPORT_CACHE_STRICT = "0"
}
if (-not $env:RELEASE_GATE_REPORT_CACHE_ASSERT_HIT -or [string]::IsNullOrWhiteSpace($env:RELEASE_GATE_REPORT_CACHE_ASSERT_HIT)) {
  $env:RELEASE_GATE_REPORT_CACHE_ASSERT_HIT = "1"
}

function Write-Info([string]$msg) { Write-Host "[INFO] $msg" }
function Write-Warn([string]$msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Fail([string]$msg) { Write-Host "[FAIL] $msg" -ForegroundColor Red }

function Assert-GitRepo {
  git rev-parse --is-inside-work-tree *> $null
  if ($LASTEXITCODE -ne 0) { throw "현재 폴더가 Git 레포가 아닙니다." }
}

function Assert-CleanWorkingTree {
  $status = git status --porcelain
  if ($status -and $status.Trim().Length -gt 0) {
    throw "작업트리가 clean이 아닙니다. 커밋/스태시 후 다시 시도하세요.`n$status"
  }
}

function Checkout-And-Pull([string]$branch) {
  Write-Info "브랜치 전환: $branch"
  git checkout $branch | Out-Null
  Write-Info "원격 최신화: $Remote/$branch"
  git pull $Remote $branch | Out-Null
}

function Wait-HealthAny([string[]]$urls, [hashtable]$headers, [int]$timeoutSec = 15) {
  $start = Get-Date
  while (((Get-Date) - $start).TotalSeconds -lt $timeoutSec) {
    foreach ($u in $urls) {
      try {
        $r = Invoke-WebRequest -Uri $u -Method Get -TimeoutSec 3 -Headers $headers -ErrorAction Stop
        if ($r.StatusCode -eq 200) { return $u }
      } catch {
        # ignore and try next
      }
    }
    Start-Sleep -Milliseconds 500
  }
  return $null
}

function Get-HealthCandidates([string]$baseUrl, [string]$healthUrl) {
  if ($healthUrl -and $healthUrl.Trim().Length -gt 0) {
    return @($healthUrl)
  }
  return @(
    "$baseUrl/health",
    "$baseUrl/ping",
    "$baseUrl/info"
  )
}

function Start-ServerIfNeeded([string]$baseUrl, [string]$healthUrl) {
  $candidates = Get-HealthCandidates $baseUrl $healthUrl
  $headers = @{ "x-company-id" = "HEALTH"; "x-role" = "VIEWER" }
  $found = Wait-HealthAny $candidates $headers 1
  if ($found) {
    Write-Info "서버 헬스 OK: $found"
    $script:ResolvedHealthUrl = $found
    return $null
  }

  if (-not $env:MES_MASTER_KEY) {
    throw "MES_MASTER_KEY 환경변수가 없습니다. 서버 실행 전 설정하세요."
  }

  Write-Info "서버 자동 기동: node src/server.js"
  $proc = Start-Process -FilePath node -ArgumentList "src/server.js" -PassThru
  $found2 = Wait-HealthAny $candidates $headers 15
  if (-not $found2) {
    try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
    $msg = "Health 엔드포인트를 찾지 못했습니다. -HealthUrl로 직접 지정하세요. (시도: " + ($candidates -join ", ") + ")"
    throw $msg
  }
  $script:ResolvedHealthUrl = $found2
  Write-Info "서버 헬스 OK: $found2"
  return $proc
}

function Run-Smoke {
  Write-Info "smoke 실행"
  & pwsh -NoProfile -ExecutionPolicy Bypass -File "scripts/smoke.ps1"
  if ($LASTEXITCODE -ne 0) { throw "smoke 실패" }
}

function Set-ErdEnv {
  if ($ErdMermaid) { $env:SMOKE_GEN_ERD = "1" }
  if ($ErdRender) { $env:SMOKE_GEN_ERD_RENDER = "1" }
  if ($ErdStrict) { $env:SMOKE_GEN_ERD_STRICT = "1" }
  if ($ErdEnforce) { $env:SMOKE_GEN_ERD_ENFORCE = "1" }
}

function Clear-ErdEnv {
  Remove-Item Env:SMOKE_GEN_ERD,Env:SMOKE_GEN_ERD_RENDER,Env:SMOKE_GEN_ERD_STRICT,Env:SMOKE_GEN_ERD_ENFORCE -ErrorAction SilentlyContinue
}

function Set-PurgeProbeEnv {
  if (-not $env:RELEASE_PROBE_PURGE) { $env:RELEASE_PROBE_PURGE = "1" }
  if (-not $env:RELEASE_PROBE_PURGE_STRICT) { $env:RELEASE_PROBE_PURGE_STRICT = "1" }
}

function Clear-PurgeProbeEnv {
  Remove-Item Env:RELEASE_PROBE_PURGE,Env:RELEASE_PROBE_PURGE_STRICT -ErrorAction SilentlyContinue
}

function Invoke-GatewaySmokeIfEnabled {
  param(
    [Parameter(Mandatory = $true)][string]$BaseUrl
  )

  if ($env:RELEASE_PROBE_GATEWAY -ne "1") {
    Write-Info "Gateway probe: SKIP (RELEASE_PROBE_GATEWAY != 1)"
    return
  }

  $gatewayDir = Join-Path $PSScriptRoot "..\edge-gateway"
  $gatewayDir = (Resolve-Path $gatewayDir).Path
  $smokePath = Join-Path $gatewayDir "scripts\smoke-gateway.ps1"
  $nodeModules = Join-Path $gatewayDir "node_modules"

  if (!(Test-Path $smokePath)) {
    throw "Gateway probe requested but not found: $smokePath"
  }
  if (!(Test-Path $nodeModules)) {
    $msg = "Gateway probe SKIP: node_modules 없음. 실행하려면 `"$gatewayDir`"에서 npm ci 필요"
    if ($env:RELEASE_PROBE_GATEWAY_STRICT -eq "1") { throw $msg }
    Write-Warn $msg
    return
  }

  Write-Info "Gateway probe: RUN (edge-gateway smoke)"

  $oldBaseUrl = $env:MES_BASE_URL
  $oldCompanyId = $env:MES_COMPANY_ID

  try {
    $env:MES_BASE_URL = $BaseUrl
    if (-not $env:MES_COMPANY_ID) { $env:MES_COMPANY_ID = "COMPANY-A" }

    Push-Location $gatewayDir
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $smokePath
    if ($LASTEXITCODE -ne 0) { throw "Gateway smoke failed with exit code $LASTEXITCODE" }
  }
  finally {
    Pop-Location

    if ($null -ne $oldBaseUrl) { $env:MES_BASE_URL = $oldBaseUrl } else { Remove-Item Env:MES_BASE_URL -ErrorAction SilentlyContinue }
    if ($null -ne $oldCompanyId) { $env:MES_COMPANY_ID = $oldCompanyId } else { Remove-Item Env:MES_COMPANY_ID -ErrorAction SilentlyContinue }
  }

  Write-Info "Gateway probe: PASS"
}

function Invoke-ReportCacheProbe {
  param(
    [string]$BaseUrl,
    [string]$HealthUrl,
    [hashtable]$Headers,
    [ref]$ServerProcRef
  )

  $probe = ($env:RELEASE_GATE_REPORT_CACHE_PROBE -eq "1")
  if (-not $probe) { return }

  $strict = ($env:RELEASE_GATE_REPORT_CACHE_STRICT -eq "1")
  $assertHit = ($env:RELEASE_GATE_REPORT_CACHE_ASSERT_HIT -ne "0")

  $from = (Get-Date).AddDays(-7).ToString("yyyy-MM-dd")
  $to = (Get-Date).ToString("yyyy-MM-dd")

  Write-Info "REPORT 캐시 probe 시작 (mode=$env:REPORT_KPI_CACHE_MODE, from=$from, to=$to)"

  # 서버를 PREFER 모드로 재기동(가능한 경우)
  if ($ServerProcRef.Value) {
    Write-Info "REPORT_KPI_CACHE_MODE=PREFER로 서버 재기동"
    try { Stop-Process -Id $ServerProcRef.Value.Id -Force -ErrorAction SilentlyContinue } catch {}
    $env:REPORT_KPI_CACHE_MODE = "PREFER"

    $proc = Start-Process -FilePath node -ArgumentList "src/server.js" -PassThru
    $candidates = Get-HealthCandidates $BaseUrl $HealthUrl
    $found = Wait-HealthAny $candidates $Headers 15
    if (-not $found) {
      try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
      $msg = "REPORT_KPI probe 실패: 서버 재기동 후 헬스 체크 실패"
      if ($strict) { throw $msg } else { Write-Warn $msg; return }
    }
    $script:ResolvedHealthUrl = $found
    $ServerProcRef.Value = $proc
  } else {
    $msg = "REPORT_KPI probe: 서버를 자동 기동한 상태가 아니므로 재기동을 건너뜁니다."
    if ($strict) { throw $msg } else { Write-Warn $msg }
  }

  try {
    $summaryUrl = "$BaseUrl/api/v1/reports/summary?from=$from&to=$to"
    $dailyUrl = "$BaseUrl/api/v1/reports/daily?from=$from&to=$to"

    $respSummary = Invoke-WebRequest -Uri $summaryUrl -Method Get -Headers $Headers -TimeoutSec 5
    if ($respSummary.StatusCode -ne 200) {
      throw "summary expected 200, got $($respSummary.StatusCode)"
    }
    Write-Info "REPORT 캐시 probe 200 OK: $summaryUrl"

    $respDaily1 = Invoke-WebRequest -Uri $dailyUrl -Method Get -Headers $Headers -TimeoutSec 5
    if ($respDaily1.StatusCode -ne 200) {
      throw "daily 1st expected 200, got $($respDaily1.StatusCode)"
    }
    Write-Info "REPORT 캐시 probe 200 OK: $dailyUrl (1st)"

    $respDaily2 = Invoke-WebRequest -Uri $dailyUrl -Method Get -Headers $Headers -TimeoutSec 5
    if ($respDaily2.StatusCode -ne 200) {
      throw "daily 2nd expected 200, got $($respDaily2.StatusCode)"
    }
    $cacheHeader = $respDaily2.Headers["X-Report-Cache"]
    Write-Info "REPORT 캐시 probe 200 OK: $dailyUrl (2nd), X-Report-Cache=$cacheHeader"

    if ($assertHit -and $cacheHeader -ne "HIT") {
      throw "REPORT 캐시 HIT 미증명: X-Report-Cache=HIT 필요, 실제='$cacheHeader'"
    }
  } catch {
    $msg = "REPORT_KPI probe 요청 실패: $($_.Exception.Message)"
    if ($strict) { throw $msg } else { Write-Warn $msg; return }
  }
  Write-Info "REPORT 캐시 probe 완료"
}

function Get-NextTag([string]$series) {
  $args = @("tools/baseline-tag.ps1")
  if ($series) { $args += @("-Series", $series) }
  $out = & pwsh -NoProfile -ExecutionPolicy Bypass @args
  $tag = ($out | Where-Object { $_ -match '^baseline-v\d+\.\d+\.\d+$' } | Select-Object -First 1)
  if (-not $tag) { throw "다음 태그를 계산하지 못했습니다." }
  return $tag
}

Assert-GitRepo
Assert-CleanWorkingTree

Checkout-And-Pull $Branch

$serverProc = $null
try {
  $serverProc = Start-ServerIfNeeded $BaseUrl $HealthUrl
  $probeGatewayEffective = $ProbeGateway -or $ApplyTag -or $PushTag
  if ($probeGatewayEffective) {
    $env:RELEASE_PROBE_GATEWAY = "1"
  } else {
    Remove-Item Env:RELEASE_PROBE_GATEWAY -ErrorAction SilentlyContinue
  }
  Set-ErdEnv
  Set-PurgeProbeEnv
  Run-Smoke
  Clear-PurgeProbeEnv
  Invoke-GatewaySmokeIfEnabled -BaseUrl $BaseUrl
  Remove-Item Env:RELEASE_PROBE_GATEWAY -ErrorAction SilentlyContinue
  Clear-ErdEnv

  $headers = @{ "x-company-id" = "HEALTH"; "x-role" = "VIEWER" }
  Invoke-ReportCacheProbe -BaseUrl $BaseUrl -HealthUrl $HealthUrl -Headers $headers -ServerProcRef ([ref]$serverProc)
} finally {
  if ($serverProc) {
    Write-Info "서버 종료"
    try { Stop-Process -Id $serverProc.Id -Force -ErrorAction SilentlyContinue } catch {}
  }
}

$erdEnabled = $ErdMermaid -or $ErdRender -or $ErdEnforce
if ($erdEnabled) {
  $erdDirty = & git status --porcelain -- "docs/erd/*.mmd"
  if ($erdDirty) {
    throw "ERD 생성으로 docs/erd/*.mmd 변경이 생겼습니다. 커밋 후 다시 실행하거나, ERD 옵션을 끄고 실행하세요."
  }
}

$nextTag = Get-NextTag $Series
Write-Info "다음 baseline 태그: $nextTag"

if ($ApplyTag) {
  Write-Warn "태그 생성 모드(-ApplyTag)입니다."
  & pwsh -NoProfile -ExecutionPolicy Bypass -File "tools/baseline-tag.ps1" @(
    if ($Series) { "-Series"; $Series } else { $null }
    if ($PushTag) { "-Push" } else { $null }
    "-Apply"
  ) | Where-Object { $_ -ne $null } | ForEach-Object { $_ }
} else {
  Write-Info "DryRun 완료(태그 생성 없음)."
}

if ($MergeMain) {
  Checkout-And-Pull "main"
  git merge --no-ff $Branch -m "chore: release $nextTag" | Out-Null
  git push $Remote main | Out-Null

  if ($SmokeOnMain) {
    $serverProc2 = $null
    try {
      $serverProc2 = Start-ServerIfNeeded $HealthUrl
      Run-Smoke
    } finally {
      if ($serverProc2) {
        Write-Info "서버 종료(main)"
        try { Stop-Process -Id $serverProc2.Id -Force -ErrorAction SilentlyContinue } catch {}
      }
    }
  }
}
