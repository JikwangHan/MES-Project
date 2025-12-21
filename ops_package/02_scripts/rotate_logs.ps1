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
  [int]$ArchiveRetentionDays = 180,
  [int]$EvidenceRetentionDays = 365,
  [string]$ArchiveSubdir = "logs\\archive\\weekly",
  [switch]$Compress
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$LogsDir = Join-Path $RepoRoot "logs"
$EvidenceDir = Join-Path $RepoRoot "ops_package\05_evidence"
$ArchiveDir = Join-Path $RepoRoot $ArchiveSubdir
$EvidenceArchiveDir = Join-Path $EvidenceDir "archive"

function Ensure-Dir([string]$Path) {
  if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null }
}

function Get-OldFiles([string]$Path, [datetime]$Cutoff) {
  if (-not (Test-Path $Path)) { return @() }
  return Get-ChildItem -Path $Path -File -Recurse |
    Where-Object { $_.LastWriteTime -lt $Cutoff }
}

$cutoffLogs = (Get-Date).AddDays(-1 * $RetentionDays)
$cutoffArchive = (Get-Date).AddDays(-1 * $ArchiveRetentionDays)
$cutoffEvidence = (Get-Date).AddDays(-1 * $EvidenceRetentionDays)
$cutoffRecent = (Get-Date).AddHours(-24)

Write-Host "==> 정책: logs $RetentionDays 일, archive $ArchiveRetentionDays 일, evidence $EvidenceRetentionDays 일"

$oldLogs = @(
  Get-OldFiles -Path $LogsDir -Cutoff $cutoffLogs |
    Where-Object { $_.FullName -notmatch '\\archive\\' } |
    Where-Object { $_.LastWriteTime -lt $cutoffRecent } |
    Where-Object { $_.Extension -notin @('.env', '.key') }
)

$oldEvidence = @(
  Get-OldFiles -Path $EvidenceDir -Cutoff $cutoffEvidence |
    Where-Object { $_.FullName -notmatch '\\archive\\' } |
    Where-Object { $_.LastWriteTime -lt $cutoffRecent }
)

$oldArchives = @(
  Get-OldFiles -Path $ArchiveDir -Cutoff $cutoffArchive
)

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

  if ($oldArchives.Count -gt 0) {
    $oldArchives | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host "==> archive 정리 완료 (삭제)"
  } else {
    Write-Host "==> archive 정리 대상 없음"
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

  if ($oldArchives.Count -gt 0) {
    $oldArchives | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host "==> archive 정리 완료 (삭제)"
  } else {
    Write-Host "==> archive 정리 대상 없음"
  }
}
