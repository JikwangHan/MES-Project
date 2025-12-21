<# 
  ops_package/02_scripts/rotate_logs.ps1

  목적
  - logs/ 및 ops_package/05_evidence/ 안의 오래된 로그를 정리합니다.
  - 필요하면 압축(zip)까지 수행합니다.

  기본값
  - 30일 이전 파일 정리
#>

param(
  [int]$RetentionDays = 30,
  [switch]$Compress
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$LogsDir = Join-Path $RepoRoot "logs"
$EvidenceDir = Join-Path $RepoRoot "ops_package\05_evidence"
$ArchiveDir = Join-Path $LogsDir "archive"
$EvidenceArchiveDir = Join-Path $EvidenceDir "archive"

function Ensure-Dir([string]$Path) {
  if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null }
}

function Get-OldFiles([string]$Path, [datetime]$Cutoff) {
  if (-not (Test-Path $Path)) { return @() }
  return Get-ChildItem -Path $Path -File -Recurse |
    Where-Object { $_.LastWriteTime -lt $Cutoff }
}

$cutoff = (Get-Date).AddDays(-1 * $RetentionDays)
Write-Host "==> 보관 기준: $RetentionDays 일 이전 파일 정리"

$oldLogs = Get-OldFiles -Path $LogsDir -Cutoff $cutoff | Where-Object { $_.FullName -notmatch '\\archive\\' }
$oldEvidence = Get-OldFiles -Path $EvidenceDir -Cutoff $cutoff | Where-Object { $_.FullName -notmatch '\\archive\\' }

if ($Compress) {
  Ensure-Dir $ArchiveDir
  Ensure-Dir $EvidenceArchiveDir
  $stamp = (Get-Date).ToString("yyyyMMdd")

  if ($oldLogs.Count -gt 0) {
    $zip = Join-Path $ArchiveDir "logs_$stamp.zip"
    Compress-Archive -Path $oldLogs.FullName -DestinationPath $zip -Force
    $oldLogs | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host "==> logs 압축 완료: $zip"
  } else {
    Write-Host "==> logs 압축 대상 없음"
  }

  if ($oldEvidence.Count -gt 0) {
    $zip = Join-Path $EvidenceArchiveDir "evidence_$stamp.zip"
    Compress-Archive -Path $oldEvidence.FullName -DestinationPath $zip -Force
    $oldEvidence | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host "==> evidence 압축 완료: $zip"
  } else {
    Write-Host "==> evidence 압축 대상 없음"
  }
} else {
  if ($oldLogs.Count -gt 0) {
    $oldLogs | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host "==> logs 정리 완료 (삭제)"
  } else {
    Write-Host "==> logs 정리 대상 없음"
  }

  if ($oldEvidence.Count -gt 0) {
    $oldEvidence | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host "==> evidence 정리 완료 (삭제)"
  } else {
    Write-Host "==> evidence 정리 대상 없음"
  }
}
