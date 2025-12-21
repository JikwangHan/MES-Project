<# 
  ops_package/02_scripts/build_handover_bundle.ps1

  목적
  - 최신 OPS_Package ZIP + evidence ZIP + 핵심 문서를 묶어
    최종 제출용 ZIP을 만듭니다.
#>

param(
  [string]$Version = "v0.1"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$DistDir = Join-Path $RepoRoot "ops_package\\06_dist"
$EvidenceDir = Join-Path $RepoRoot "ops_package\\05_evidence"

function Latest-File([string]$Path, [string]$Filter) {
  if (-not (Test-Path $Path)) { return $null }
  return Get-ChildItem -Path $Path -Filter $Filter -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}

$opsZip = Latest-File -Path $DistDir -Filter ("OPS_Package_{0}_*.zip" -f $Version)
$eviZip = Latest-File -Path $EvidenceDir -Filter "evidence_*.zip"

$handoverDoc = Join-Path $RepoRoot "ops_package\\03_docs\\HANDOVER_SUBMISSION_1PAGE.md"
$sopDoc = Join-Path $RepoRoot "ops_package\\03_docs\\SOP_v0.1.md"
$hardeningDoc = Join-Path $RepoRoot "ops_package\\03_docs\\HARDENING_1PAGE.md"
$checklistDoc = Join-Path $RepoRoot "docs\\testing\\Ticket-17.2_Test_Checklist.md"

if (-not $opsZip) { Write-Host "[FAIL] OPS_Package ZIP 없음"; return }
if (-not $eviZip) { Write-Host "[FAIL] evidence ZIP 없음"; return }

$stamp = (Get-Date).ToString("yyyyMMdd_HHmm")
$bundleZip = Join-Path $DistDir ("HANDOVER_BUNDLE_{0}_{1}.zip" -f $Version, $stamp)

$files = @(
  $opsZip.FullName,
  $eviZip.FullName
)
if (Test-Path $handoverDoc) { $files += $handoverDoc }
if (Test-Path $sopDoc) { $files += $sopDoc }
if (Test-Path $hardeningDoc) { $files += $hardeningDoc }
if (Test-Path $checklistDoc) { $files += $checklistDoc }

Compress-Archive -Path $files -DestinationPath $bundleZip -Force

Write-Host "[PASS] HANDOVER 번들 ZIP 생성 완료: $bundleZip"
