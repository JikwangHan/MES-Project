<# 
  ops_package/02_scripts/check_capture_sanity.ps1

  목적
  - 캡처 #1~#6 필수 파일이 있는지만 확인합니다.
  - 이미지 내용 분석/비밀값 검사는 하지 않습니다.
  - 파일 생성/삭제/수정은 하지 않습니다.
#>

param(
  [string]$SessionId,
  [string]$CaptureDir,
  [string[]]$Extensions = @("png", "jpg", "jpeg")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$capturesRoot = Join-Path $RepoRoot "ops_package\\05_evidence\\captures"

function Get-LatestSessionDir {
  if (-not (Test-Path $capturesRoot)) { return $null }
  $dirs = Get-ChildItem -Path $capturesRoot -Directory |
    Where-Object { $_.Name -match '^\d{8}_\d{4}$' } |
    Sort-Object Name -Descending
  return $dirs | Select-Object -First 1
}

if (-not $CaptureDir -or $CaptureDir -eq "") {
  if ($SessionId -and $SessionId -ne "") {
    $CaptureDir = Join-Path $capturesRoot $SessionId
  } else {
    $latest = Get-LatestSessionDir
    if ($latest) {
      $CaptureDir = $latest.FullName
      $SessionId = $latest.Name
    }
  }
}

if (-not $CaptureDir -or -not (Test-Path $CaptureDir)) {
  Write-Host "[FAIL] 캡처 폴더를 찾을 수 없습니다."
  Write-Host "       -SessionId 또는 -CaptureDir를 지정하세요."
  exit 1
}

if (-not $SessionId -or $SessionId -eq "") {
  $SessionId = Split-Path $CaptureDir -Leaf
}

$required = @(
  "01_service_status",
  "02_health_200",
  "03_ticket17_2_p0_pass",
  "04_selfcheck_pass",
  "05_evidence_zip_list",
  "06_handover_bundle_list"
)

$missing = @()
$duplicates = @()

foreach ($key in $required) {
  $hits = @()
  foreach ($ext in $Extensions) {
    $pattern = "{0}_{1}.{2}" -f $SessionId, $key, $ext
    $hits += Get-ChildItem -Path $CaptureDir -Filter $pattern -File -ErrorAction SilentlyContinue
  }
  if ($hits.Count -eq 0) {
    $missing += $key
  } elseif ($hits.Count -gt 1) {
    $duplicates += $key
  }
}

if ($missing.Count -gt 0) {
  Write-Host "[FAIL] Missing captures ($($required.Count - $missing.Count)/$($required.Count))"
  Write-Host "누락 항목:"
  $missing | ForEach-Object { Write-Host " - $_" }
  exit 1
}

Write-Host "[PASS] Capture sanity OK ($($required.Count)/$($required.Count))"
if ($duplicates.Count -gt 0) {
  Write-Host "[WARN] duplicates found:"
  $duplicates | ForEach-Object { Write-Host " - $_" }
}
