<# 
  scripts/ops/load_dotenv.ps1

  목적
  - 레포 루트의 .env 파일을 읽어 KEY=VALUE 형식의 값을 환경변수로 주입합니다.
  - 이미 환경변수가 있는 경우에는 덮어쓰지 않습니다. (운영 환경 우선)

  주의
  - 이 스크립트는 키 값을 출력하지 않습니다.
#>

param(
  [string]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Trim-Quotes([string]$Value) {
  if ($Value -match '^".*"$') { return $Value.Trim('"') }
  if ($Value -match "^'.*'$") { return $Value.Trim("'") }
  return $Value
}

if (-not $Path -or $Path -eq "") {
  return
}

if (-not (Test-Path $Path)) {
  return
}

$lines = Get-Content -Path $Path -Encoding utf8
foreach ($line in $lines) {
  if (-not $line) { continue }
  $trim = $line.Trim()
  if ($trim -eq "" -or $trim.StartsWith("#")) { continue }
  $eq = $trim.IndexOf("=")
  if ($eq -lt 1) { continue }
  $key = $trim.Substring(0, $eq).Trim()
  $value = $trim.Substring($eq + 1).Trim()
  $value = Trim-Quotes $value

  if ($key -and -not [Environment]::GetEnvironmentVariable($key, "Process")) {
    [Environment]::SetEnvironmentVariable($key, $value, "Process")
  }
}
