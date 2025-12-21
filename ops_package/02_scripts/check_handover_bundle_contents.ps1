<# 
  ops_package/02_scripts/check_handover_bundle_contents.ps1

  목적
  - HANDOVER_BUNDLE ZIP 안에 캡처 6장이 실제 포함됐는지 확인합니다.
  - 파일명/확장자 존재 여부만 검사합니다. (내용 분석/비밀값 검사는 하지 않음)
#>

param(
  [string]$BundleZipPath,
  [string]$SessionId,
  [string[]]$Extensions = @("png", "jpg", "jpeg")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$DistDir = Join-Path $RepoRoot "ops_package\\06_dist"

function Latest-File([string]$Path, [string]$Filter) {
  if (-not (Test-Path $Path)) { return $null }
  return Get-ChildItem -Path $Path -Filter $Filter -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}

if (-not $BundleZipPath -or $BundleZipPath -eq "") {
  $latest = Latest-File -Path $DistDir -Filter "HANDOVER_BUNDLE_*.zip"
  if ($latest) { $BundleZipPath = $latest.FullName }
}

if (-not $BundleZipPath -or -not (Test-Path $BundleZipPath)) {
  Write-Host "[FAIL] 번들 ZIP을 찾을 수 없습니다."
  exit 1
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

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($BundleZipPath)
try {
  $entries = $zip.Entries | ForEach-Object { $_.FullName }

  foreach ($key in $required) {
    $hits = @()
    foreach ($ext in $Extensions) {
      $pattern = if ($SessionId -and $SessionId -ne "") {
        "$SessionId`_$key.$ext"
      } else {
        "*_$key.$ext"
      }
      $hits += $entries | Where-Object { $_ -like $pattern }
    }

    if ($hits.Count -eq 0) {
      $missing += $key
    } elseif ($hits.Count -gt 1) {
      $duplicates += $key
    }
  }
} finally {
  $zip.Dispose()
}

if ($missing.Count -gt 0) {
  Write-Host "[FAIL] Missing in bundle ($($required.Count - $missing.Count)/$($required.Count))"
  Write-Host "누락 항목:"
  $missing | ForEach-Object { Write-Host " - $_" }
  exit 1
}

Write-Host "[PASS] Bundle contains required captures ($($required.Count)/$($required.Count))"
if ($duplicates.Count -gt 0) {
  Write-Host "[WARN] duplicates found:"
  $duplicates | ForEach-Object { Write-Host " - $_" }
}
