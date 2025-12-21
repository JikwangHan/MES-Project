<# 
  ops_package/02_scripts/judge_handover_ready.ps1

  목적
  - 제출 직전 “최종 판정 1줄”을 출력합니다.
  - 파일 존재 여부만 확인하며, 내용 분석/비밀값 검사는 하지 않습니다.
#>

param(
  [string]$SessionId,
  [string]$BundleZipPath,
  [string]$EvidenceZipPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$capturesRoot = Join-Path $RepoRoot "ops_package\\05_evidence\\captures"
$distDir = Join-Path $RepoRoot "ops_package\\06_dist"
$evidenceDir = Join-Path $RepoRoot "ops_package\\05_evidence"

function Latest-File([string]$Path, [string]$Filter) {
  if (-not (Test-Path $Path)) { return $null }
  return Get-ChildItem -Path $Path -Filter $Filter -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}

function Latest-SessionId {
  if (-not (Test-Path $capturesRoot)) { return $null }
  $dir = Get-ChildItem -Path $capturesRoot -Directory |
    Where-Object { $_.Name -match '^\d{8}_\d{4}$' } |
    Sort-Object Name -Descending |
    Select-Object -First 1
  if ($dir) { return $dir.Name }
  return $null
}

if (-not $SessionId -or $SessionId -eq "") {
  $SessionId = Latest-SessionId
}

if (-not $BundleZipPath -or $BundleZipPath -eq "") {
  $bundle = Latest-File -Path $distDir -Filter "HANDOVER_BUNDLE_*.zip"
  if ($bundle) { $BundleZipPath = $bundle.FullName }
}

if (-not $EvidenceZipPath -or $EvidenceZipPath -eq "") {
  $evi = Latest-File -Path $evidenceDir -Filter "evidence_*.zip"
  if ($evi) { $EvidenceZipPath = $evi.FullName }
}

$failReasons = @()
$warnReasons = @()

if (-not $SessionId) { $failReasons += "세션ID 없음" }
if (-not $BundleZipPath -or -not (Test-Path $BundleZipPath)) { $failReasons += "번들 ZIP 없음" }

# 캡처 sanity 검사
if ($SessionId) {
  $capCheck = Join-Path $RepoRoot "ops_package\\02_scripts\\check_capture_sanity.ps1"
  if (Test-Path $capCheck) {
    & $capCheck -SessionId $SessionId
    if ($LASTEXITCODE -ne 0) { $failReasons += "캡처 6/6 실패" }
  } else {
    $failReasons += "check_capture_sanity.ps1 없음"
  }
}

# 번들 내용 검사
if ($BundleZipPath -and (Test-Path $BundleZipPath)) {
  $bundleCheck = Join-Path $RepoRoot "ops_package\\02_scripts\\check_handover_bundle_contents.ps1"
  if (Test-Path $bundleCheck) {
    if ($SessionId) {
      & $bundleCheck -BundleZipPath $BundleZipPath -SessionId $SessionId
    } else {
      & $bundleCheck -BundleZipPath $BundleZipPath
    }
    if ($LASTEXITCODE -ne 0) { $failReasons += "번들 캡처 6/6 실패" }
  } else {
    $failReasons += "check_handover_bundle_contents.ps1 없음"
  }
}

# evidence ZIP은 선택(없으면 WARN)
if (-not $EvidenceZipPath -or -not (Test-Path $EvidenceZipPath)) {
  $warnReasons += "evidence ZIP 없음"
}

if ($failReasons.Count -eq 0) {
  $msg = "[PASS] HANDOVER READY (session=$SessionId, bundle=$BundleZipPath)"
  if ($warnReasons.Count -gt 0) {
    $msg += " | WARN: " + ($warnReasons -join ", ")
  }
  Write-Host $msg
  exit 0
}

Write-Host ("[FAIL] HANDOVER NOT READY: " + ($failReasons -join ", "))
exit 1
