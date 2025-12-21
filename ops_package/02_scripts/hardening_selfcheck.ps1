<# 
  ops_package/02_scripts/hardening_selfcheck.ps1

  목적
  - 운영 서버 하드닝 점검을 빠르게 확인합니다.
  - 시스템 설정을 변경하지 않고, 상태만 점검합니다.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

# .env 로딩 (환경변수가 있으면 덮어쓰지 않음)
$dotenv = Join-Path $RepoRoot "scripts\ops\load_dotenv.ps1"
$envPath = Join-Path $RepoRoot ".env"
if (Test-Path $dotenv) {
  . $dotenv -Path $envPath
}

$pass = 0
$fail = 0

function Record([string]$Status, [string]$TestId, [string]$Message) {
  Write-Host "[$Status] $TestId $Message"
  if ($Status -eq "PASS") { $script:pass += 1 } else { $script:fail += 1 }
}

# 1) MES_BASE_URL 유효성 및 포트 추출
$baseUrl = $env:MES_BASE_URL
if (-not $baseUrl) { $baseUrl = "http://localhost:4000" }
try {
  $uri = [Uri]::new($baseUrl)
  Record "PASS" "HARDENING-01" "MES_BASE_URL 유효 ($baseUrl)"
} catch {
  Record "FAIL" "HARDENING-01" "MES_BASE_URL 형식 오류 ($baseUrl)"
  $uri = $null
}

# 2) 포트 LISTEN 여부
if ($uri) {
  $port = $uri.Port
  try {
    $listening = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($listening) {
      Record "PASS" "HARDENING-02" "포트 LISTEN 확인 ($port)"
    } else {
      Record "FAIL" "HARDENING-02" "포트 LISTEN 미확인 ($port)"
    }
  } catch {
    Record "FAIL" "HARDENING-02" "포트 확인 실패 ($port)"
  }
}

# 3) logs/windows_service 폴더 접근
$logDir = Join-Path $RepoRoot "logs\\windows_service"
if (Test-Path $logDir) {
  $testFile = Join-Path $logDir ("_write_test_{0}.tmp" -f (Get-Date).ToString("yyyyMMdd_HHmmss"))
  try {
    "test" | Out-File -FilePath $testFile -Encoding utf8
    Remove-Item $testFile -Force -ErrorAction SilentlyContinue
    Record "PASS" "HARDENING-03" "logs/windows_service 쓰기 가능"
  } catch {
    Record "FAIL" "HARDENING-03" "logs/windows_service 쓰기 불가"
  }
} else {
  Record "FAIL" "HARDENING-03" "logs/windows_service 폴더 없음"
}

# 4) .env 존재 여부 (내용 출력 금지)
if (Test-Path $envPath) {
  Record "PASS" "HARDENING-04" ".env 존재 확인"
} else {
  Record "FAIL" "HARDENING-04" ".env 없음"
}

# 5) 서비스 상태 확인
$svcName = "MES-WebServer"
$svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq "Running") {
  Record "PASS" "HARDENING-05" "서비스 Running ($svcName)"
} elseif ($svc) {
  Record "FAIL" "HARDENING-05" "서비스 상태: $($svc.Status) ($svcName)"
} else {
  Record "FAIL" "HARDENING-05" "서비스 없음 ($svcName)"
}

# 6) 디스크 여유율 확인
try {
  $drive = $RepoRoot.Substring(0, 1) + ":"
  $disk = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='" + $drive + "'")
  if ($disk -and $disk.Size -gt 0) {
    $freePct = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)
    if ($freePct -lt 5) {
      Record "FAIL" "HARDENING-06" "디스크 여유율 낮음 ($freePct`%)"
    } elseif ($freePct -lt 15) {
      Write-Host "[WARN] HARDENING-06 디스크 여유율 경고 ($freePct`%)"
    } else {
      Record "PASS" "HARDENING-06" "디스크 여유율 정상 ($freePct`%)"
    }
  }
} catch {
  Write-Host "[WARN] HARDENING-06 디스크 여유율 확인 실패"
}

Write-Host "==> 결과: PASS=$pass, FAIL=$fail"
