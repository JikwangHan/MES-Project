<# 
codex-bundle-generate.ps1

목적:
- 레포 루트에서 실행하면 package.json scripts, smoke.ps1, perf-gate.ps1, 폴더 구조를 스캔
- .codex/ 아래에 레포 맞춤형 Codex 운영 파일을 생성

주의:
- 추측 금지: 실제 파일을 읽어 확인합니다.
- 이번 작업은 .codex 생성이 목적이며, 제품 기능 코드는 건드리지 않습니다.
#>

$ErrorActionPreference = "Stop"

function Write-Info($msg) { Write-Host "[codex-bundle] $msg" -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Host "[codex-bundle] $msg" -ForegroundColor Yellow }

$ROOT = (Get-Location).Path
$OUT  = Join-Path $ROOT ".codex"
$LOCAL_TEMPLATES = Join-Path $PSScriptRoot "..\templates"
$REPO_TEMPLATES  = Join-Path $ROOT "templates"

# 제외 폴더(속도/안전)
$IgnoreRegex = "\\.git\\|\\node_modules\\|\\dist\\|\\build\\|\\out\\|\\.next\\|\\coverage\\|\\bin\\|\\obj\\"

function Load-Template($name) {
  $p1 = Join-Path $REPO_TEMPLATES $name
  if (Test-Path $p1) { return Get-Content $p1 -Raw -Encoding UTF8 }

  $p2 = Join-Path $LOCAL_TEMPLATES $name
  if (Test-Path $p2) { return Get-Content $p2 -Raw -Encoding UTF8 }

  throw "템플릿을 찾을 수 없습니다: $name"
}

function Render($template, $vars) {
  $out = $template
  foreach ($k in $vars.Keys) {
    $token = "{{{0}}}" -f $k
    $out = $out.Replace($token, [string]$vars[$k])
  }
  return $out
}

function Format-ScriptsSummary($scripts) {
  if ($null -eq $scripts -or $scripts.Count -eq 0) { return "- (package.json scripts 없음)" }
  $keys = $scripts.Keys | Sort-Object
  return ($keys | ForEach-Object { "- {0}: {1}" -f $_, $scripts[$_] }) -join "`n"
}

function Score-File($fullPath) {
  $norm = $fullPath.Replace("\", "/").ToLower()
  $score = 1000
  if ($norm -match "/scripts/") { $score -= 300 }
  if ($norm -match "/tools/")   { $score -= 200 }
  if ($norm -match "/smoke\.ps1$") { $score -= 50 }
  if ($norm -match "/perf-gate\.ps1$") { $score -= 50 }

  $rel = (Resolve-Path $fullPath).Path.Substring($ROOT.Length).TrimStart("\")
  $depth = ($rel -split "[\\/]").Length
  $score += ($depth * 2)
  return $score
}

function Choose-Best($paths) {
  if ($null -eq $paths -or $paths.Count -eq 0) { return $null }
  return $paths | Sort-Object @{ Expression = { Score-File $_ } } | Select-Object -First 1
}

function Find-File($name) {
  $hits = Get-ChildItem -Path $ROOT -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ieq $name -and $_.FullName -notmatch $IgnoreRegex } |
    Select-Object -ExpandProperty FullName
  return $hits
}

function Make-Cmds($scripts, $smokePath, $perfPath) {
  function ScriptCmd($keys) {
    foreach ($k in $keys) {
      if ($scripts.ContainsKey($k)) { return "npm run $k" }
    }
    return "N/A"
  }

  $cmdLint = ScriptCmd @("lint","lint:fix","eslint")
  $cmdTest = ScriptCmd @("test","test:unit","test:ci")

  $cmdSmoke = if ($smokePath) { "powershell -ExecutionPolicy Bypass -File .\{0}" -f ((Resolve-Path $smokePath).Path.Substring($ROOT.Length).TrimStart("\")) } else { "N/A" }
  $cmdPerf  = if ($perfPath)  { "powershell -ExecutionPolicy Bypass -File .\{0}" -f ((Resolve-Path $perfPath).Path.Substring($ROOT.Length).TrimStart("\")) } else { "N/A" }

  return @{ cmdLint=$cmdLint; cmdTest=$cmdTest; cmdSmoke=$cmdSmoke; cmdPerf=$cmdPerf }
}

Write-Info "레포 루트: $ROOT"

# package.json 스캔
$pkgPath = Join-Path $ROOT "package.json"
$scripts = @{}
if (Test-Path $pkgPath) {
  $pkg = Get-Content $pkgPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($null -ne $pkg.scripts) {
    $pkg.scripts.PSObject.Properties | ForEach-Object { $scripts[$_.Name] = [string]$_.Value }
  }
  Write-Info "package.json: OK"
} else {
  Write-Warn "package.json: 없음"
}

# smoke/perf-gate 찾기
$smokeHits = Find-File "smoke.ps1"
$perfHits  = Find-File "perf-gate.ps1"

$smokePath = Choose-Best $smokeHits
$perfPath  = Choose-Best $perfHits

Write-Info ("smoke.ps1: {0}" -f ($(if($smokePath){ $smokePath.Substring($ROOT.Length).TrimStart("\") } else { "없음" })))
Write-Info ("perf-gate.ps1: {0}" -f ($(if($perfPath){ $perfPath.Substring($ROOT.Length).TrimStart("\") } else { "없음" })))

$cmds = Make-Cmds $scripts $smokePath $perfPath

# .codex 생성
New-Item -ItemType Directory -Force -Path $OUT | Out-Null

$vars = @{
  SCRIPTS_SUMMARY = (Format-ScriptsSummary $scripts)
  SMOKE_PATH      = $(if($smokePath){ $smokePath.Substring($ROOT.Length).TrimStart("\") } else { "N/A" })
  PERF_GATE_PATH  = $(if($perfPath){  $perfPath.Substring($ROOT.Length).TrimStart("\")  } else { "N/A" })
  CMD_LINT        = $cmds.cmdLint
  CMD_TEST        = $cmds.cmdTest
  CMD_SMOKE       = $cmds.cmdSmoke
  CMD_PERF        = $cmds.cmdPerf
}

Set-Content -Encoding UTF8 -Path (Join-Path $OUT "AGENTS.md") -Value (Render (Load-Template "AGENTS.template.md") $vars)
Set-Content -Encoding UTF8 -Path (Join-Path $OUT "PLANS.md") -Value (Render (Load-Template "PLANS.template.md") $vars)
Set-Content -Encoding UTF8 -Path (Join-Path $OUT "TICKET_PROMPTS.md") -Value (Render (Load-Template "TICKET_PROMPTS.template.md") $vars)
Set-Content -Encoding UTF8 -Path (Join-Path $OUT "QUALITY_GATE_CHECKLIST.md") -Value (Render (Load-Template "QUALITY_GATE_CHECKLIST.template.md") $vars)
Set-Content -Encoding UTF8 -Path (Join-Path $OUT "SESSION_START_PROMPT.md") -Value (Render (Load-Template "SESSION_START_PROMPT.template.md") $vars)

$report = @"
# codex-scan-report.md

## 스캔 요약
- 레포 루트: $ROOT
- package.json: $(if(Test-Path $pkgPath){"있음"} else {"없음"})
- smoke.ps1: $($vars.SMOKE_PATH)
- perf-gate.ps1: $($vars.PERF_GATE_PATH)

## 감지된 npm scripts
$($vars.SCRIPTS_SUMMARY)

## 품질 게이트(복붙용)
- lint: $($vars.CMD_LINT)
- test: $($vars.CMD_TEST)
- smoke: $($vars.CMD_SMOKE)
- perf-gate: $($vars.CMD_PERF)

## 생성된 파일
- .codex/AGENTS.md
- .codex/PLANS.md
- .codex/TICKET_PROMPTS.md
- .codex/QUALITY_GATE_CHECKLIST.md
- .codex/SESSION_START_PROMPT.md
"@
Set-Content -Encoding UTF8 -Path (Join-Path $OUT "codex-scan-report.md") -Value $report

Write-Info "Done: .codex/ created"
