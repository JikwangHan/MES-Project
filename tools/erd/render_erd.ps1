<# tools/erd/render_erd.ps1
목적:
- Mermaid .mmd 파일을 PNG/PDF로 렌더링합니다.
- 기본 구현은 npx로 @mermaid-js/mermaid-cli(mmdc)를 호출합니다.

사용 예:
pwsh tools/erd/render_erd.ps1 -Input "docs/erd/mes_erd.mmd" -OutDir "docs/erd"

운영 옵션:
- 인터넷이 막힌 환경에서는 npx 설치가 실패할 수 있습니다.
  이 경우:
  1) 개발 PC에서 1회 npm i -D @mermaid-js/mermaid-cli 수행(레포에 package-lock 반영)
  2) 또는 CI에서 캐시 사용
#>

param(
  [Parameter(Mandatory=$true)][string]$Input,
  [Parameter(Mandatory=$true)][string]$OutDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Info($m) { Write-Host "[ERD] $m" }
function Write-Warn($m) { Write-Host "[ERD][WARN] $m" }
function Write-Fail($m) { throw $m }

if (!(Test-Path $Input)) {
  Write-Fail "입력 Mermaid 파일이 없습니다: $Input"
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$png = Join-Path $OutDir "mes_erd.png"
$pdf = Join-Path $OutDir "mes_erd.pdf"

# 1) mmdc 사용 가능 여부 체크 (로컬 설치 우선)
$mmdcCmd = $null
try {
  $mmdcCmd = (Get-Command mmdc -ErrorAction Stop).Source
} catch {
  $mmdcCmd = $null
}

function Invoke-Mmdc($outFile, $format) {
  if ($mmdcCmd) {
    Write-Info "로컬 mmdc 사용: $mmdcCmd"
    & $mmdcCmd -i $Input -o $outFile | Out-Null
    return
  }

  # npx로 실행(필요 시 다운로드)
  Write-Info "npx로 mmdc 실행(@mermaid-js/mermaid-cli). 네트워크 환경에 따라 시간이 걸릴 수 있습니다."
  & npx -y @mermaid-js/mermaid-cli -i $Input -o $outFile | Out-Null
}

Write-Info "PNG 렌더링 시작 → $png"
Invoke-Mmdc $png "png"
Write-Info "PNG 렌더링 완료"

Write-Info "PDF 렌더링 시작 → $pdf"
Invoke-Mmdc $pdf "pdf"
Write-Info "PDF 렌더링 완료"

Write-Info "렌더링 산출물: $png , $pdf"
