<# 
  ops_package/02_scripts/prepare_capture_session.ps1

  목적
  - 캡처 세션 폴더를 만들고, 캡처 인덱스를 자동 생성합니다.
#>

param(
  [string]$SessionId,
  [string]$OutputDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

if (-not $SessionId -or $SessionId -eq "") {
  $SessionId = (Get-Date).ToString("yyyyMMdd_HHmm")
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$capturesRoot = Join-Path $RepoRoot "ops_package\\05_evidence\\captures"
if (-not $OutputDir -or $OutputDir -eq "") {
  $OutputDir = Join-Path $capturesRoot $SessionId
}

if (-not (Test-Path $OutputDir)) {
  New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

$template = Join-Path $RepoRoot "ops_package\\03_docs\\CAPTURE_INDEX_TEMPLATE.md"
$indexPath = Join-Path $OutputDir ("CAPTURE_INDEX_{0}.md" -f $SessionId)

$header = @(
  "# 캡처 인덱스 ($SessionId)",
  "",
  "아래 파일명으로 캡처를 저장하세요.",
  ""
) -join "`n"

$names = @(
  "{0}_01_service_status.png" -f $SessionId,
  "{0}_02_health_200.png" -f $SessionId,
  "{0}_03_ticket17_2_p0_pass.png" -f $SessionId,
  "{0}_04_selfcheck_pass.png" -f $SessionId,
  "{0}_05_evidence_zip_list.png" -f $SessionId,
  "{0}_06_handover_bundle_list.png" -f $SessionId
)

$body = $names | ForEach-Object { "- $_" } | Out-String

if (Test-Path $template) {
  $content = $header + "`n" + $body + "`n`n---`n" + (Get-Content -Path $template -Raw)
  $content | Out-File -FilePath $indexPath -Encoding utf8
} else {
  ($header + "`n" + $body) | Out-File -FilePath $indexPath -Encoding utf8
}

Write-Host "[PASS] 캡처 세션 폴더 생성: $OutputDir"
Write-Host "[PASS] 캡처 인덱스 생성: $indexPath"
Write-Host "파일명 예시:"
$names | ForEach-Object { Write-Host " - $_" }
