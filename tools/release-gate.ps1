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
  [switch]$ErdEnforce
)

$ErrorActionPreference = "Stop"

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

function Wait-HealthAny([string[]]$urls, [int]$timeoutSec = 15) {
  $start = Get-Date
  while (((Get-Date) - $start).TotalSeconds -lt $timeoutSec) {
    foreach ($u in $urls) {
      try {
        $r = Invoke-WebRequest -Uri $u -Method Get -TimeoutSec 3 -ErrorAction Stop
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
  $found = Wait-HealthAny $candidates 1
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
  $found2 = Wait-HealthAny $candidates 15
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
  Set-ErdEnv
  Run-Smoke
} finally {
  Clear-ErdEnv
  if ($serverProc) {
    Write-Info "서버 종료"
    try { Stop-Process -Id $serverProc.Id -Force -ErrorAction SilentlyContinue } catch {}
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
