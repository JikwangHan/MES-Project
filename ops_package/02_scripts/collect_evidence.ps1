<# 
  ops_package/02_scripts/collect_evidence.ps1

  목적
  - 운영 증빙을 한 번에 수집하여 ZIP으로 묶습니다.
  - .env 등 비밀 파일은 절대 포함하지 않습니다.
#>

param(
  [int]$MaxFiles = 10,
  [int]$SinceDays = 7
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$LogsDir = Join-Path $RepoRoot "logs"
$Checklist = Join-Path $RepoRoot "docs\testing\Ticket-17.2_Test_Checklist.md"
$ReleaseNotes = Join-Path $RepoRoot "RELEASE_NOTES.md"
$SopDoc = Join-Path $RepoRoot "ops_package\03_docs\SOP_v0.1.md"
$EvidenceDir = Join-Path $RepoRoot "ops_package\05_evidence"

function Ensure-Dir([string]$Path) {
  if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null }
}

Ensure-Dir $EvidenceDir
$stamp = (Get-Date).ToString("yyyyMMdd_HHmm")
$zipPath = Join-Path $EvidenceDir "evidence_$stamp.zip"

$cutoff = (Get-Date).AddDays(-1 * $SinceDays)
$logCandidates = @()
if (Test-Path $LogsDir) {
  $logCandidates = Get-ChildItem -Path $LogsDir -Filter "ticket17_2-*.log" -File |
    Where-Object { $_.LastWriteTime -ge $cutoff } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First $MaxFiles
}

$files = @()
foreach ($f in $logCandidates) { $files += $f.FullName }
if (Test-Path $Checklist) { $files += $Checklist }
if (Test-Path $ReleaseNotes) { $files += $ReleaseNotes }
if (Test-Path $SopDoc) { $files += $SopDoc }

if ($files.Count -eq 0) {
  throw "수집할 증빙 파일이 없습니다."
}

Compress-Archive -Path $files -DestinationPath $zipPath -Force
Write-Host "==> 증빙 ZIP 생성 완료: $zipPath"
