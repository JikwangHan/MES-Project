<# 
  ops_package/02_scripts/build_ops_package.ps1

  목적
  - ops_package 폴더 전체를 배포용 ZIP으로 묶습니다.
  - 민감 파일(.env)과 불필요한 항목은 제외합니다.
#>

param(
  [string]$Version = "v0.1",
  [switch]$IncludeLogs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$OpsRoot = Join-Path $RepoRoot "ops_package"
$DistDir = Join-Path $OpsRoot "06_dist"

function Ensure-Dir([string]$Path) {
  if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null }
}

Ensure-Dir $DistDir

# 최신 스크립트 동기화 (레포 기준)
$srcRun = Join-Path $RepoRoot "scripts\ops\run_ticket_17_2.ps1"
$srcEnv = Join-Path $RepoRoot "scripts\ops\load_dotenv.ps1"
$dstRun = Join-Path $OpsRoot "02_scripts\run_ticket_17_2.ps1"
$dstEnv = Join-Path $OpsRoot "02_scripts\load_dotenv.ps1"
if (Test-Path $srcRun) { Copy-Item $srcRun $dstRun -Force }
if (Test-Path $srcEnv) { Copy-Item $srcEnv $dstEnv -Force }

$stamp = (Get-Date).ToString("yyyyMMdd_HHmm")
$zipPath = Join-Path $DistDir ("OPS_Package_{0}_{1}.zip" -f $Version, $stamp)

$tempRoot = Join-Path $DistDir ("_stage_{0}" -f $stamp)
if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force }
New-Item -ItemType Directory -Path $tempRoot | Out-Null

# ops_package 전체 복사 (불필요 항목 제외)
$excludePatterns = @(
  "*.env",
  "*.zip",
  ".git",
  "node_modules"
)

$items = Get-ChildItem -Path $OpsRoot -Recurse -File
foreach ($item in $items) {
  $rel = $item.FullName.Substring($OpsRoot.Length).TrimStart('\')
  if ($excludePatterns | Where-Object { $rel -like $_ }) { continue }
  if (-not $IncludeLogs -and $rel -like "05_evidence\\*") { continue }
  if ($rel -like "06_dist\\*") { continue }

  $dest = Join-Path $tempRoot $rel
  Ensure-Dir (Split-Path $dest -Parent)
  Copy-Item $item.FullName $dest -Force
}

Compress-Archive -Path (Join-Path $tempRoot "*") -DestinationPath $zipPath -Force
Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "==> 운영 패키지 ZIP 생성 완료: $zipPath"
Write-Host "==> 포함된 항목(상위 폴더):"
Get-ChildItem -Path (Split-Path $zipPath -Parent) | Select-Object -First 1 | Out-Null
Get-ChildItem -Path $OpsRoot -Directory | ForEach-Object { Write-Host " - $($_.Name)" }
