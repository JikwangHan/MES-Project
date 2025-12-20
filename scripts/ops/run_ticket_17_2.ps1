<# 
  scripts/ops/run_ticket_17_2.ps1

  목적
  - MES smoke 및 선택적으로 gateway smoke를 실행하고, 모든 로그를 logs 폴더에 저장합니다.
  - 로그에서 PASS/FAIL 근거 라인만 추출하여 Ticket-17.2 체크리스트 문서를 자동 갱신합니다.

  설계 원칙
  - 초보자도 따라할 수 있게, 실행 순서와 결과 저장 위치를 고정합니다.
  - 네트워크가 없어도 동작하는 로컬 실행 중심입니다.
  - 기존 smoke 스크립트 출력 포맷([PASS] Ticket-xx …)을 근거 라인으로 사용합니다.
#>

param(
  [switch]$RunGatewaySmoke,
  [switch]$GatewayAutoKey,
  [string]$GatewayEquipmentCode = "EQ-GW-001"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# 레포 루트를 계산합니다. (ops 폴더 상위가 scripts, 그 상위가 레포 루트라고 가정)
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$LogsDir  = Join-Path $RepoRoot "logs"

# Ticket-17.2 체크리스트 문서 경로(없으면 새로 만듭니다)
$ChecklistPath = Join-Path $RepoRoot "docs\testing\Ticket-17.2_Test_Checklist.md"

function Ensure-Dir([string]$Path) {
  if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null }
}

function NowStamp() {
  return (Get-Date).ToString("yyyyMMdd_HHmmss")
}

function Run-Capture {
  param(
    [string]$Label,
    [string]$Exe,
    [string[]]$ArgList,
    [string]$OutFile
  )
  Write-Host "==> RUN: $Label"
  $argString = ($ArgList | ForEach-Object {
    if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
  }) -join ' '
  Write-Host "    $Exe $argString"

  Ensure-Dir (Split-Path $OutFile -Parent)
  $lines = & $Exe @ArgList 2>&1
  $lines | Out-File -FilePath $OutFile -Encoding utf8
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) {
    throw "FAILED: $Label (exit=$exitCode) -> $OutFile"
  }

  return $OutFile
}

function Extract-EvidenceLines {
  param([string]$LogPath)

  # 근거 라인 표준:
  # [PASS] Ticket-xx ...
  # [FAIL] Ticket-xx ... | reason=...
  $lines = Get-Content -Path $LogPath -Encoding utf8

  $evidence = @()
  foreach ($line in $lines) {
    if ($line -match '^\[(PASS|FAIL)\]\s+(Ticket-[0-9A-Za-z\.\-]+)\s*(.*)$') {
      $status = $matches[1]
      $testId = $matches[2]
      $title  = $matches[3].Trim()
      $evidence += [pscustomobject]@{
        Status = $status
        TestId = $testId
        Title  = $title
        Source = (Split-Path $LogPath -Leaf)
        Line   = $line.Trim()
      }
    }
  }
  return $evidence
}

function Upsert-ChecklistAutoSection {
  param(
    [string]$Path,
    [string]$AutoMarkdown
  )

  $start = "<!-- AUTO_RESULT_START -->"
  $end   = "<!-- AUTO_RESULT_END -->"

  if (-not (Test-Path $Path)) {
    Ensure-Dir (Split-Path $Path -Parent)
    $template = @(
      "# Ticket-17.2 테스트 체크리스트",
      "",
      "## 목적",
      "- MES 및 edge-gateway 단위의 테스트를 재현성 있게 수행하고, PASS/FAIL 근거 라인을 남깁니다.",
      "- 본 문서는 자동 갱신 섹션을 포함합니다.",
      "",
      "## 실행 방법",
      "- PowerShell에서 레포 루트 기준으로 아래 실행",
      "  - scripts\\ops\\run_ticket_17_2.ps1",
      "",
      "## 자동 수집 결과",
      $start,
      $end,
      "",
      "## 수동 점검 항목(필요 시)",
      "- 관리자 권한, 기업 선택 필터 동작, 원시 로그 보관, 재전송 큐 확인 등"
    ) -join "`n"
    $template | Out-File -FilePath $Path -Encoding utf8
  }

  $content = Get-Content -Path $Path -Encoding utf8 -Raw
  if ($content -notmatch [regex]::Escape($start)) {
    $content = $content + "`n## 자동 수집 결과`n$start`n$end`n"
  }

  $pattern = [regex]::Escape($start) + '.*?' + [regex]::Escape($end)
  $replacement = $start + "`n" + $AutoMarkdown + "`n" + $end
  $new = [regex]::Replace($content, $pattern, $replacement, [System.Text.RegularExpressions.RegexOptions]::Singleline)

  $new | Out-File -FilePath $Path -Encoding utf8
}

# -------------------------
# 실행 시작
# -------------------------
Ensure-Dir $LogsDir
$stamp = NowStamp

$mesSmokePs51 = Join-Path $LogsDir "ticket17_2-mes-smoke-ps51-$stamp.log"
$mesSmokePwsh = Join-Path $LogsDir "ticket17_2-mes-smoke-pwsh-$stamp.log"
$gwSmokePs51  = Join-Path $LogsDir "ticket17_2-gw-smoke-ps51-$stamp.log"

# 1) MES smoke (Windows PowerShell 5.1)
Run-Capture -Label "MES smoke (PS 5.1)" `
  -Exe "powershell.exe" `
  -ArgList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "$RepoRoot\scripts\smoke.ps1") `
  -OutFile $mesSmokePs51 | Out-Null

# 2) MES smoke (pwsh가 설치된 경우에만)
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)
if ($pwsh) {
  Run-Capture -Label "MES smoke (pwsh)" `
    -Exe "pwsh" `
    -ArgList @("-NoProfile", "-File", "$RepoRoot\scripts\smoke.ps1") `
    -OutFile $mesSmokePwsh | Out-Null
} else {
  Write-Host "==> SKIP: pwsh not found"
}

# 3) 선택: Gateway smoke
if ($RunGatewaySmoke) {
  # 환경변수는 스크립트 실행 중에만 잠시 설정하고 끝나면 원복합니다.
  $oldAutoKey = $env:SMOKE_GATEWAY_AUTO_KEY
  $oldEqCode  = $env:GATEWAY_PROFILE_EQUIPMENT_CODE

  if ($GatewayAutoKey) { $env:SMOKE_GATEWAY_AUTO_KEY = "1" } else { $env:SMOKE_GATEWAY_AUTO_KEY = $null }
  $env:GATEWAY_PROFILE_EQUIPMENT_CODE = $GatewayEquipmentCode

  try {
    Run-Capture -Label "Gateway smoke (PS 5.1)" `
      -Exe "powershell.exe" `
      -ArgList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "$RepoRoot\edge-gateway\scripts\smoke-gateway.ps1") `
      -OutFile $gwSmokePs51 | Out-Null
  } finally {
    $env:SMOKE_GATEWAY_AUTO_KEY = $oldAutoKey
    $env:GATEWAY_PROFILE_EQUIPMENT_CODE = $oldEqCode
  }
}

# 4) 근거 라인 수집 및 체크리스트 갱신
$allEvidence = @()
$allEvidence += Extract-EvidenceLines -LogPath $mesSmokePs51
if (Test-Path $mesSmokePwsh) { $allEvidence += Extract-EvidenceLines -LogPath $mesSmokePwsh }
if (Test-Path $gwSmokePs51)  { $allEvidence += Extract-EvidenceLines -LogPath $gwSmokePs51 }

# 표 형태 마크다운 생성
$auto = @()
$auto += "### 자동 실행 결과 ($stamp)"
$auto += ""
$auto += "| Status | TestId | Title | SourceLog | EvidenceLine |"
$auto += "|---|---|---|---|---|"

foreach ($e in $allEvidence) {
  $auto += "| $($e.Status) | $($e.TestId) | $($e.Title) | $($e.Source) | $($e.Line) |"
}

if ($allEvidence.Count -eq 0) {
  $auto += "| INFO | - | No evidence lines matched. Check log format. | - | - |"
}

Upsert-ChecklistAutoSection -Path $ChecklistPath -AutoMarkdown ($auto -join "`n")

Write-Host ""
Write-Host "==> DONE"
Write-Host "Logs:"
Write-Host " - $mesSmokePs51"
if (Test-Path $mesSmokePwsh) { Write-Host " - $mesSmokePwsh" }
if (Test-Path $gwSmokePs51)  { Write-Host " - $gwSmokePs51" }
Write-Host "Checklist updated:"
Write-Host " - $ChecklistPath"
