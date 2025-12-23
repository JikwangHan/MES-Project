param(
  [switch]$Copy,
  [switch]$RedactBaseUrl
)

$ErrorActionPreference = "Stop"

function Get-KstNow {
  try {
    $tz = [TimeZoneInfo]::FindSystemTimeZoneById('Korea Standard Time')
    $utc = (Get-Date).ToUniversalTime()
    $kst = [TimeZoneInfo]::ConvertTimeFromUtc($utc, $tz)
    return $kst.ToString("yyyy-MM-dd HH:mm")
  } catch {
    return (Get-Date).ToString("yyyy-MM-dd HH:mm")
  }
}

function Safe-Value([string]$Value, [string]$Fallback) {
  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $Fallback
  }
  return $Value.Trim()
}

# 운영 증빙에 필요한 최소 정보만 수집합니다. 경로/계정/토큰 등은 출력하지 않습니다.
$kst = Get-KstNow
$os = Safe-Value $env:OS "Windows"
$psVersion = Safe-Value $PSVersionTable.PSVersion.ToString() "N/A"

$nodeVersion = "N/A"
try {
  $nodeVersion = Safe-Value (& node -v 2>$null) "N/A"
} catch { }

$baseUrl = Safe-Value $env:MES_BASE_URL "N/A"
if ($RedactBaseUrl) {
  $baseUrl = "<redacted>"
}

$gitHash = "N/A"
try {
  $gitHash = Safe-Value (& git rev-parse --short HEAD 2>$null) "N/A"
} catch { }

$line = "E2E_META | KST=$kst | Env=OS=$os;PS=$psVersion;Node=$nodeVersion;MES_BASE_URL=$baseUrl | Script=smoke_e2e_p0.ps1@$gitHash"
Write-Host $line

if ($Copy) {
  try {
    Set-Clipboard -Value $line
    Write-Host "[INFO] 클립보드에 복사되었습니다."
  } catch {
    Write-Host "[WARN] 클립보드 복사 실패. 콘솔 출력값을 직접 복사하세요."
  }
}
