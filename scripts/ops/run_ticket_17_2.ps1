<# 
  scripts/ops/run_ticket_17_2.ps1

  목적
  - MES smoke 및 선택적으로 gateway smoke를 실행하고, 모든 로그를 logs 폴더에 저장합니다.
  - 로그에서 PASS/FAIL 근거 라인만 추출하여 Ticket-17.2 체크리스트 문서를 자동 갱신합니다.

  설계 원칙
  - 초보자도 따라할 수 있게, 실행 순서와 결과 저장 위치를 고정합니다.
  - 네트워크가 없어도 동작하는 로컬 실행 중심입니다.
  - 기존 smoke 스크립트 출력 포맷([PASS] Ticket-xx …)을 근거 라인으로 사용합니다.
#>

param(
  [switch]$RunGatewaySmoke,
  [switch]$GatewayAutoKey,
  [string]$GatewayEquipmentCode = "EQ-GW-001",
  [switch]$AutoStartServer,
  [switch]$DevMode,
  [switch]$IncludeP1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# 레포 루트를 계산합니다. (ops 폴더 상위가 scripts, 그 상위가 레포 루트라고 가정)
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$LogsDir  = Join-Path $RepoRoot "logs"

# Ticket-17.2 체크리스트 문서 경로(없으면 새로 만듭니다)
$ChecklistPath = Join-Path $RepoRoot "docs\testing\Ticket-17.2_Test_Checklist.md"

$BaseUrl = $env:MES_BASE_URL
if (-not $BaseUrl) { $BaseUrl = "http://localhost:4000" }
$CompanyId = $env:MES_COMPANY_ID
if (-not $CompanyId) { $CompanyId = "COMPANY-A" }
$Role = "OPERATOR"
$EquipmentCode = $env:T17_EQUIPMENT_CODE
if (-not $EquipmentCode) { $EquipmentCode = "T17-2-EQ-001" }
$CanonicalMode = "stable-json"

function Ensure-Dir([string]$Path) {
  if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null }
}

function NowStamp() {
  return (Get-Date).ToString("yyyyMMdd_HHmmss")
}

function Run-Capture {
  param(
    [string]$Label,
    [string]$Exe,
    [string[]]$ArgList,
    [string]$OutFile
  )
  Write-Host "==> RUN: $Label"
  $argString = ($ArgList | ForEach-Object {
    if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
  }) -join ' '
  Write-Host "    $Exe $argString"

  Ensure-Dir (Split-Path $OutFile -Parent)
  $oldEA = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $lines = & $Exe @ArgList 2>&1
  } finally {
    $ErrorActionPreference = $oldEA
  }
  $lines | Out-File -FilePath $OutFile -Encoding utf8
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) {
    throw "FAILED: $Label (exit=$exitCode) -> $OutFile"
  }

  return $OutFile
}

function Extract-EvidenceLines {
  param([string]$LogPath)

  # 근거 라인 표준:
  # [PASS] Ticket-17.2-XX ...
  # [FAIL] Ticket-17.2-XX ... | reason=...
  $lines = Get-Content -Path $LogPath -Encoding utf8

  $evidence = @()
  foreach ($line in $lines) {
    if ($line -match '^\[(PASS|FAIL)\]\s+(Ticket-17\.2-[0-9]{2,})\s*(.*)$') {
      $status = $matches[1]
      $testId = $matches[2]
      $title  = $matches[3].Trim()
      $evidence += [pscustomobject]@{
        Status = $status
        TestId = $testId
        Title  = $title
        Source = (Split-Path $LogPath -Leaf)
        Line   = $line.Trim()
      }
    }
  }
  return $evidence
}

function Upsert-ChecklistAutoSection {
  param(
    [string]$Path,
    [string]$AutoMarkdown
  )

  $start = "<!-- AUTO_RESULT_START -->"
  $end   = "<!-- AUTO_RESULT_END -->"

  if (-not (Test-Path $Path)) {
    Ensure-Dir (Split-Path $Path -Parent)
    $template = @(
      "# Ticket-17.2 테스트 체크리스트",
      "",
      "## 목적",
      "- MES 및 edge-gateway 단위의 테스트를 재현성 있게 수행하고, PASS/FAIL 근거 라인을 남깁니다.",
      "- 본 문서는 자동 갱신 섹션을 포함합니다.",
      "",
      "## 실행 방법",
      "- PowerShell에서 레포 루트 기준으로 아래 실행",
      "  - scripts\\ops\\run_ticket_17_2.ps1",
      "",
      "## 자동 수집 결과",
      $start,
      $end,
      "",
      "## 수동 점검 항목(필요 시)",
      "- 관리자 권한, 기업 선택 필터 동작, 원시 로그 보관, 재전송 큐 확인 등"
    ) -join "`n"
    $template | Out-File -FilePath $Path -Encoding utf8
  }

  $content = Get-Content -Path $Path -Encoding utf8 -Raw
  if ($content -notmatch [regex]::Escape($start)) {
    $content = $content + "`n## 자동 수집 결과`n$start`n$end`n"
  }

  $pattern = [regex]::Escape($start) + '.*?' + [regex]::Escape($end)
  $replacement = $start + "`n" + $AutoMarkdown + "`n" + $end
  $new = [regex]::Replace($content, $pattern, $replacement, [System.Text.RegularExpressions.RegexOptions]::Singleline)

  $new | Out-File -FilePath $Path -Encoding utf8
}

function Invoke-CurlJson {
  param(
    [string]$Method,
    [string]$Url,
    [hashtable]$Headers,
    [string]$Body = $null,
    [string]$BodyFile = $null
  )
  $respPath = New-TemporaryFile
  $args = @('-s', '-o', $respPath, '-w', '%{http_code}', '-X', $Method, '--url', $Url)
  foreach ($k in $Headers.Keys) {
    $args += @('-H', "$($k): $($Headers[$k])")
  }
  if ($BodyFile) {
    $args += @('--data', "@$BodyFile")
  } elseif ($null -ne $Body -and $Body -ne "") {
    $args += @('--data', $Body)
  }
  $status = & curl.exe @args
  $raw = ''
  if (Test-Path $respPath) {
    $raw = Get-Content $respPath -Raw
    Remove-Item $respPath -Force -ErrorAction SilentlyContinue
  }
  $json = $null
  if ($raw) {
    try { $json = $raw | ConvertFrom-Json } catch { }
  }
  return @{ Status = $status; Raw = $raw; Json = $json }
}

function Sha256Hex([string]$Text) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ""
}

function HmacSha256Hex([string]$Secret, [string]$Canonical) {
  $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($Secret)
  $h = New-Object System.Security.Cryptography.HMACSHA256 -ArgumentList (,$keyBytes)
  $msgBytes = [System.Text.Encoding]::UTF8.GetBytes($Canonical)
  ($h.ComputeHash($msgBytes) | ForEach-Object { $_.ToString("x2") }) -join ""
}

function ConvertTo-StableJson {
  param([Parameter(Mandatory=$true)][object]$Obj)

  function Normalize($v) {
    if ($null -eq $v) { return $null }
    if ($v -is [hashtable] -or $v.PSObject.TypeNames[0] -eq 'System.Management.Automation.PSCustomObject') {
      $ht = [ordered]@{}
      $props = @()
      if ($v -is [hashtable]) { $props = $v.Keys } else { $props = $v.PSObject.Properties.Name }
      foreach ($k in ($props | Sort-Object)) {
        $val = if ($v -is [hashtable]) { $v[$k] } else { $v.$k }
        $ht[$k] = Normalize $val
      }
      return $ht
    }
    if ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) {
      $arr = @()
      foreach ($x in $v) { $arr += ,(Normalize $x) }
      return $arr
    }
    return $v
  }

  $n = Normalize $Obj
  return ($n | ConvertTo-Json -Depth 50 -Compress)
}

function Write-T17Line {
  param(
    [string]$Status,
    [string]$TestId,
    [string]$Message,
    [string]$LogPath
  )
  $line = "[$Status] $TestId $Message"
  Write-Host $line
  $line | Out-File -FilePath $LogPath -Encoding utf8 -Append
}

function Get-ErrorCode {
  param($Resp)
  if ($Resp -and $Resp.Json -and $Resp.Json.error -and $Resp.Json.error.code) {
    return $Resp.Json.error.code
  }
  return "-"
}

function Ensure-EquipmentAndKey {
  param([string]$LogPath)
  $headers = @{
    "x-company-id" = $CompanyId
    "x-role" = $Role
    "Content-Type" = "application/json"
  }

  $list = Invoke-CurlJson "GET" "$BaseUrl/api/v1/equipments" $headers
  if ($list.Status -ne "200") {
    $script:EnsureError = "equipment 목록 조회 실패 (status=$($list.Status))"
    return $null
  }
  $equip = $list.Json.data | Where-Object { $_.code -eq $EquipmentCode } | Select-Object -First 1
  if (-not $equip) {
    $bodyObj = @{
      name = "T17-2 장비"
      code = $EquipmentCode
      commType = "HTTP"
      commConfig = @{ url = "http://dummy" }
      isActive = 1
    }
    $bodyJson = ($bodyObj | ConvertTo-Json -Depth 10 -Compress)
    $create = Invoke-CurlJson "POST" "$BaseUrl/api/v1/equipments" $headers $bodyJson
    if ($create.Status -ne "201" -and $create.Status -ne "409") {
      $script:EnsureError = "equipment 생성 실패 (status=$($create.Status))"
      $list = Invoke-CurlJson "GET" "$BaseUrl/api/v1/equipments" $headers
      $equip = $list.Json.data | Select-Object -First 1
    } else {
      $list = Invoke-CurlJson "GET" "$BaseUrl/api/v1/equipments" $headers
      $equip = $list.Json.data | Where-Object { $_.code -eq $EquipmentCode } | Select-Object -First 1
    }
  }

  if (-not $equip) {
    if (-not $script:EnsureError) {
      $script:EnsureError = "equipment 조회 실패 (code=$EquipmentCode)"
    }
    return $null
  }

  $issue = Invoke-CurlJson "POST" "$BaseUrl/api/v1/equipments/$($equip.id)/device-key" $headers "{}"
  if ($issue.Status -ne "201" -and $issue.Status -ne "200") {
    $script:EnsureError = "device-key 발급 실패 (status=$($issue.Status))"
    return $null
  }
  $script:EnsureError = $null
  return @{
    EquipmentId = $equip.id
    EquipmentCode = $equip.code
    DeviceKeyId = $issue.Json.data.deviceKeyId
    DeviceSecret = $issue.Json.data.deviceSecret
  }
}

function Send-SignedTelemetry {
  param(
    [string]$DeviceKeyId,
    [string]$DeviceSecret,
    [string]$EquipmentCodeValue,
    [string]$Nonce,
    [int]$Ts,
    [string]$CanonicalOverride = $CanonicalMode
  )

  $payload = @{
    equipmentCode = $EquipmentCodeValue
    eventType = "TELEMETRY"
    payload = @{
      state = "RUN"
      speed = 123
    }
  }

  $bodyRaw = ConvertTo-StableJson $payload
  $bodyHash = Sha256Hex $bodyRaw
  $canonical = "$CompanyId`n$DeviceKeyId`n$Ts`n$Nonce`n$bodyHash"
  $signature = HmacSha256Hex $DeviceSecret $canonical

  $headers = @{
    "x-company-id" = $CompanyId
    "x-role" = $Role
    "x-device-key" = $DeviceKeyId
    "x-ts" = "$Ts"
    "x-nonce" = $Nonce
    "x-signature" = $signature
    "x-canonical" = $CanonicalOverride
    "Content-Type" = "application/json"
  }

  $tmpBody = New-TemporaryFile
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($tmpBody, $bodyRaw, $utf8NoBom)
  $resp = Invoke-CurlJson "POST" "$BaseUrl/api/v1/telemetry/events" $headers $null $tmpBody
  Remove-Item $tmpBody -Force -ErrorAction SilentlyContinue
  $resp.BodyRaw = $bodyRaw
  return $resp
}

function Send-TelemetryCustom {
  param(
    [hashtable]$Headers,
    [string]$BodyRaw
  )
  $tmpBody = New-TemporaryFile
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($tmpBody, $BodyRaw, $utf8NoBom)
  $resp = Invoke-CurlJson "POST" "$BaseUrl/api/v1/telemetry/events" $Headers $null $tmpBody
  Remove-Item $tmpBody -Force -ErrorAction SilentlyContinue
  $resp.BodyRaw = $BodyRaw
  return $resp
}

function Test-Health {
  try {
    $headers = @{ "x-company-id" = $CompanyId; "x-role" = "VIEWER" }
    $resp = Invoke-WebRequest -Uri "$BaseUrl/health" -Headers $headers -TimeoutSec 3 -UseBasicParsing
    return ($resp.StatusCode -eq 200)
  } catch {
    return $false
  }
}

function Start-ServerIfNeeded {
  if (Test-Health) {
    return $null
  }

  if (-not $AutoStartServer) {
    throw "서버가 실행 중이 아닙니다. -AutoStartServer 옵션을 사용하세요."
  }

  if (-not $env:MES_MASTER_KEY) {
    if ($DevMode) {
      $env:MES_MASTER_KEY = "dev-master-key"
    } else {
      throw "MES_MASTER_KEY가 없습니다. 운영 모드에서는 설정이 필요합니다."
    }
  }

  Write-Host "==> 서버가 실행 중이 아닙니다. node src/server.js로 자동 시작합니다."
  $proc = Start-Process -FilePath "node" -ArgumentList "src/server.js" -WorkingDirectory $RepoRoot -PassThru
  $limit = (Get-Date).AddSeconds(15)
  while ((Get-Date) -lt $limit) {
    if (Test-Health) { return $proc }
    Start-Sleep -Milliseconds 500
  }

  if ($proc) {
    try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
  }
  throw "서버 헬스 확인 실패: $BaseUrl/health"
}

# -------------------------
# 실행 시작
# -------------------------
Ensure-Dir $LogsDir
$stamp = NowStamp

$mesSmokePs51 = Join-Path $LogsDir "ticket17_2-mes-smoke-ps51-$stamp.log"
$mesSmokePwsh = Join-Path $LogsDir "ticket17_2-mes-smoke-pwsh-$stamp.log"
$gwSmokePs51  = Join-Path $LogsDir "ticket17_2-gw-smoke-ps51-$stamp.log"
$ticketLog    = Join-Path $LogsDir "ticket17_2-cases-$stamp.log"
$ticketErrLog = Join-Path $LogsDir "ticket17_2-errors-$stamp.log"

$serverProc = Start-ServerIfNeeded

# 1) MES smoke (Windows PowerShell 5.1)
Run-Capture -Label "MES smoke (PS 5.1)" `
  -Exe "powershell.exe" `
  -ArgList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "$RepoRoot\scripts\smoke.ps1") `
  -OutFile $mesSmokePs51 | Out-Null

# 2) MES smoke (pwsh가 설치된 경우에만)
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)
if ($pwsh) {
  Run-Capture -Label "MES smoke (pwsh)" `
    -Exe "pwsh" `
    -ArgList @("-NoProfile", "-File", "$RepoRoot\scripts\smoke.ps1") `
    -OutFile $mesSmokePwsh | Out-Null
} else {
  Write-Host "==> SKIP: pwsh not found"
}

# 3) 선택: Gateway smoke
if ($RunGatewaySmoke) {
  # 환경변수는 스크립트 실행 중에만 잠시 설정하고 끝나면 원복합니다.
  $oldAutoKey = $env:SMOKE_GATEWAY_AUTO_KEY
  $oldEqCode  = $env:GATEWAY_PROFILE_EQUIPMENT_CODE

  if ($GatewayAutoKey) { $env:SMOKE_GATEWAY_AUTO_KEY = "1" } else { $env:SMOKE_GATEWAY_AUTO_KEY = $null }
  $env:GATEWAY_PROFILE_EQUIPMENT_CODE = $GatewayEquipmentCode

  try {
    Run-Capture -Label "Gateway smoke (PS 5.1)" `
      -Exe "powershell.exe" `
      -ArgList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "$RepoRoot\edge-gateway\scripts\smoke-gateway.ps1") `
      -OutFile $gwSmokePs51 | Out-Null
  } finally {
    $env:SMOKE_GATEWAY_AUTO_KEY = $oldAutoKey
    $env:GATEWAY_PROFILE_EQUIPMENT_CODE = $oldEqCode
  }
}

# 4) Ticket-17.2 전용 테스트 실행
$passCount = 0
$failCount = 0

function Record-Result {
  param([string]$Status, [string]$TestId, [string]$Message)
  Write-T17Line $Status $TestId $Message $ticketLog
  if ($Status -eq "PASS") { $script:passCount += 1 } else { $script:failCount += 1 }
}

# 4-1) Health 200
$healthHeaders = @{ "x-company-id" = $CompanyId; "x-role" = "VIEWER" }
$health = Invoke-CurlJson "GET" "$BaseUrl/health" $healthHeaders
if ($health.Status -eq "200") {
  Record-Result "PASS" "Ticket-17.2-01" "health 200 확인"
} else {
  Record-Result "FAIL" "Ticket-17.2-01" "health 실패 (status=$($health.Status))"
}

# 4-2) 장비/키 준비
$ek = Ensure-EquipmentAndKey -LogPath $ticketLog
if (-not $ek) {
  $msg = $script:EnsureError
  if (-not $msg) { $msg = "telemetry 준비 실패(장비키 없음)" }
  Record-Result "FAIL" "Ticket-17.2-02" $msg
  Record-Result "FAIL" "Ticket-17.2-03" "telemetry 준비 실패(장비키 없음)"
} else {
  Record-Result "PASS" "Ticket-17.2-02" "device-key 발급 성공"
  # 4-3) 정상 telemetry
  $ts = [int][Math]::Floor((Get-Date).ToUniversalTime().Subtract([datetime]'1970-01-01').TotalSeconds)
  $nonce = [guid]::NewGuid().ToString("N")
  $ok = Send-SignedTelemetry -DeviceKeyId $ek.DeviceKeyId -DeviceSecret $ek.DeviceSecret -EquipmentCodeValue $ek.EquipmentCode -Nonce $nonce -Ts $ts
  if ($ok.Status -eq "201") {
    Record-Result "PASS" "Ticket-17.2-03" "telemetry 정상 업로드 201"
  } else {
    $code = Get-ErrorCode $ok
    if ($ok.Raw) { $ok.Raw | Out-File -FilePath $ticketErrLog -Encoding utf8 -Append }
    if ($ok.BodyRaw) { "BODY:$($ok.BodyRaw)" | Out-File -FilePath $ticketErrLog -Encoding utf8 -Append }
    Record-Result "FAIL" "Ticket-17.2-03" "telemetry 정상 업로드 실패 (status=$($ok.Status), code=$code)"
  }

  # 4-4) 서명 불일치
  $bad = $ok
  $badNonce = [guid]::NewGuid().ToString("N")
  $badSig = Send-SignedTelemetry -DeviceKeyId $ek.DeviceKeyId -DeviceSecret ($ek.DeviceSecret + "x") -EquipmentCodeValue $ek.EquipmentCode -Nonce $badNonce -Ts $ts
  if ($badSig.Status -eq "401") {
    Record-Result "PASS" "Ticket-17.2-04" "서명 불일치 거부 401"
  } else {
    $code = Get-ErrorCode $badSig
    if ($badSig.Raw) { $badSig.Raw | Out-File -FilePath $ticketErrLog -Encoding utf8 -Append }
    if ($badSig.BodyRaw) { "BODY:$($badSig.BodyRaw)" | Out-File -FilePath $ticketErrLog -Encoding utf8 -Append }
    Record-Result "FAIL" "Ticket-17.2-04" "서명 불일치 거부 실패 (status=$($badSig.Status), code=$code)"
  }

  # 4-5) nonce 재사용
  $replayNonce = [guid]::NewGuid().ToString("N")
  $first = Send-SignedTelemetry -DeviceKeyId $ek.DeviceKeyId -DeviceSecret $ek.DeviceSecret -EquipmentCodeValue $ek.EquipmentCode -Nonce $replayNonce -Ts $ts
  $second = Send-SignedTelemetry -DeviceKeyId $ek.DeviceKeyId -DeviceSecret $ek.DeviceSecret -EquipmentCodeValue $ek.EquipmentCode -Nonce $replayNonce -Ts $ts
  if ($first.Status -eq "201" -and $second.Status -eq "401") {
    Record-Result "PASS" "Ticket-17.2-05" "nonce 재사용 거부 401"
  } else {
    $code = Get-ErrorCode $second
    if ($first.Raw) { $first.Raw | Out-File -FilePath $ticketErrLog -Encoding utf8 -Append }
    if ($second.Raw) { $second.Raw | Out-File -FilePath $ticketErrLog -Encoding utf8 -Append }
    if ($first.BodyRaw) { "BODY:$($first.BodyRaw)" | Out-File -FilePath $ticketErrLog -Encoding utf8 -Append }
    if ($second.BodyRaw) { "BODY:$($second.BodyRaw)" | Out-File -FilePath $ticketErrLog -Encoding utf8 -Append }
    Record-Result "FAIL" "Ticket-17.2-05" "nonce 재사용 거부 실패 (1st=$($first.Status), 2nd=$($second.Status), code=$code)"
  }

  # 4-6) equipmentCode 누락
  $ts2 = $ts + 1
  $nonce2 = [guid]::NewGuid().ToString("N")
  $payload = @{ eventType = "TELEMETRY"; payload = @{ state = "RUN" } }
  $bodyRaw = ConvertTo-StableJson $payload
  $bodyHash = Sha256Hex $bodyRaw
  $canonical = "$CompanyId`n$($ek.DeviceKeyId)`n$ts2`n$nonce2`n$bodyHash"
  $signature = HmacSha256Hex $ek.DeviceSecret $canonical
  $headers = @{
    "x-company-id" = $CompanyId
    "x-role" = $Role
    "x-device-key" = $ek.DeviceKeyId
    "x-ts" = "$ts2"
    "x-nonce" = $nonce2
    "x-signature" = $signature
    "x-canonical" = $CanonicalMode
    "Content-Type" = "application/json"
  }
  $tmpBody2 = New-TemporaryFile
  $utf8NoBom2 = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($tmpBody2, $bodyRaw, $utf8NoBom2)
  $missingCode = Invoke-CurlJson "POST" "$BaseUrl/api/v1/telemetry/events" $headers $null $tmpBody2
  Remove-Item $tmpBody2 -Force -ErrorAction SilentlyContinue
  if ($missingCode.Status -eq "400") {
    Record-Result "PASS" "Ticket-17.2-06" "equipmentCode 누락 400"
  } else {
    Record-Result "FAIL" "Ticket-17.2-06" "equipmentCode 누락 거부 실패 (status=$($missingCode.Status))"
  }
}

# 4-7) Gateway smoke 결과 확인 (옵션)
if ($RunGatewaySmoke) {
  if (Test-Path $gwSmokePs51) {
    $gwLines = Get-Content -Path $gwSmokePs51 -Encoding utf8
    if ($gwLines -match "\[gateway\] uplink ok 201") {
      Record-Result "PASS" "Ticket-17.2-07" "gateway uplink 201 확인"
    } else {
      Record-Result "FAIL" "Ticket-17.2-07" "gateway uplink 201 미확인"
    }
  } else {
    Record-Result "FAIL" "Ticket-17.2-07" "gateway 로그 없음"
  }
}

# 4-8) raw log 생성 확인 (옵션)
if ($RunGatewaySmoke) {
  $rawDir = Join-Path $RepoRoot "edge-gateway\data\rawlogs"
  if (Test-Path $rawDir) {
    $rawFile = Get-ChildItem -Path $rawDir -Filter "raw_*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($rawFile) {
      Record-Result "PASS" "Ticket-17.2-08" "raw log 생성 확인 ($($rawFile.Name))"
    } else {
      Record-Result "FAIL" "Ticket-17.2-08" "raw log 파일 없음"
    }
  } else {
    Record-Result "FAIL" "Ticket-17.2-08" "raw log 폴더 없음"
  }
}

# 4-9) ~ 4-12) P1 확장 테스트 (선택)
if (-not $IncludeP1) {
  Write-Host "==> P1 테스트는 SKIP 됩니다. (필요 시 -IncludeP1 옵션 사용)"
}

if ($IncludeP1 -and $ek) {
  $tsP1 = [int][Math]::Floor((Get-Date).ToUniversalTime().Subtract([datetime]'1970-01-01').TotalSeconds)
  $nonceP1 = [guid]::NewGuid().ToString("N")
  $payloadP1 = @{
    equipmentCode = $ek.EquipmentCode
    eventType = "TELEMETRY"
    payload = @{ state = "RUN"; speed = 1 }
  }
  $bodyRawP1 = ConvertTo-StableJson $payloadP1

  # 4-9) 잘못된 deviceKeyId
  $headersBadKey = @{
    "x-company-id" = $CompanyId
    "x-role" = $Role
    "x-device-key" = [guid]::NewGuid().ToString()
    "x-ts" = "$tsP1"
    "x-nonce" = $nonceP1
    "x-signature" = "deadbeef"
    "x-canonical" = $CanonicalMode
    "Content-Type" = "application/json"
  }
  $badKey = Send-TelemetryCustom -Headers $headersBadKey -BodyRaw $bodyRawP1
  if ($badKey.Status -eq "401") {
    Record-Result "PASS" "Ticket-17.2-09" "잘못된 deviceKeyId 거부 401"
  } else {
    Record-Result "FAIL" "Ticket-17.2-09" "잘못된 deviceKeyId 거부 실패 (status=$($badKey.Status))"
  }

  # 4-10) 잘못된 ts 형식
  $headersBadTs = $headersBadKey.Clone()
  $headersBadTs["x-device-key"] = $ek.DeviceKeyId
  $headersBadTs["x-ts"] = "abc"
  $badTs = Send-TelemetryCustom -Headers $headersBadTs -BodyRaw $bodyRawP1
  if ($badTs.Status -eq "401") {
    Record-Result "PASS" "Ticket-17.2-10" "잘못된 ts 거부 401"
  } else {
    Record-Result "FAIL" "Ticket-17.2-10" "잘못된 ts 거부 실패 (status=$($badTs.Status))"
  }

  # 4-11) 만료 ts
  $headersExpired = $headersBadKey.Clone()
  $headersExpired["x-device-key"] = $ek.DeviceKeyId
  $headersExpired["x-ts"] = "$($tsP1 - 1000)"
  $expired = Send-TelemetryCustom -Headers $headersExpired -BodyRaw $bodyRawP1
  if ($expired.Status -eq "401") {
    Record-Result "PASS" "Ticket-17.2-11" "만료 ts 거부 401"
  } else {
    Record-Result "FAIL" "Ticket-17.2-11" "만료 ts 거부 실패 (status=$($expired.Status))"
  }

  # 4-12) 서명 헤더 누락
  $headersMissing = @{
    "x-company-id" = $CompanyId
    "x-role" = $Role
    "Content-Type" = "application/json"
  }
  $missingSig = Send-TelemetryCustom -Headers $headersMissing -BodyRaw $bodyRawP1
  if ($missingSig.Status -eq "401") {
    Record-Result "PASS" "Ticket-17.2-12" "서명 헤더 누락 거부 401"
  } else {
    Record-Result "FAIL" "Ticket-17.2-12" "서명 헤더 누락 거부 실패 (status=$($missingSig.Status))"
  }
} elseif ($IncludeP1 -and -not $ek) {
  Record-Result "FAIL" "Ticket-17.2-09" "P1 선행 조건 실패 (device-key 없음)"
  Record-Result "FAIL" "Ticket-17.2-10" "P1 선행 조건 실패 (device-key 없음)"
  Record-Result "FAIL" "Ticket-17.2-11" "P1 선행 조건 실패 (device-key 없음)"
  Record-Result "FAIL" "Ticket-17.2-12" "P1 선행 조건 실패 (device-key 없음)"
}

# 5) 근거 라인 수집 및 체크리스트 갱신
$allEvidence = @()
$allEvidence += Extract-EvidenceLines -LogPath $ticketLog

# 표 형태 마크다운 생성
$auto = @()
$auto += "### 자동 실행 결과 ($stamp)"
$auto += ""
$auto += "| Status | TestId | Title | SourceLog | EvidenceLine |"
$auto += "|---|---|---|---|---|"

foreach ($e in $allEvidence) {
  $auto += "| $($e.Status) | $($e.TestId) | $($e.Title) | $($e.Source) | $($e.Line) |"
}

if ($allEvidence.Count -eq 0) {
  $auto += "| INFO | - | No evidence lines matched. Check log format. | - | - |"
}

Upsert-ChecklistAutoSection -Path $ChecklistPath -AutoMarkdown ($auto -join "`n")

Write-Host ""
Write-Host "==> DONE"
Write-Host "Logs:"
Write-Host " - $mesSmokePs51"
if (Test-Path $mesSmokePwsh) { Write-Host " - $mesSmokePwsh" }
if (Test-Path $gwSmokePs51)  { Write-Host " - $gwSmokePs51" }
Write-Host " - $ticketLog"
if (Test-Path $ticketErrLog) { Write-Host " - $ticketErrLog" }
Write-Host "Results: PASS=$passCount, FAIL=$failCount"
Write-Host "Checklist updated:"
Write-Host " - $ChecklistPath"

if ($serverProc) {
  Write-Host "==> 자동으로 시작한 서버를 종료합니다."
  try { Stop-Process -Id $serverProc.Id -Force -ErrorAction SilentlyContinue } catch {}
}
