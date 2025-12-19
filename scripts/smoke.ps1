# 간단 스모크 테스트 (PowerShell + curl.exe)
# 전제: 서버가 이미 실행 중이어야 합니다. (npm start)
# 검증: 품목유형 생성 → 품목 2개 생성 → BOM 생성/조회 → 실패 케이스 1개

set-strictmode -version latest
$ErrorActionPreference = "Stop"

function Assert-SuccessJson($text) {
  if ($text -notmatch '"success":\s*true') {
    throw "응답이 success:true 가 아닙니다.`n$text"
  }
}

function Assert-FailJson($text) {
  if ($text -notmatch '"success":\s*false') {
    throw "응답이 success:false 가 아닙니다.`n$text"
  }
}

function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }

$baseUrl = "http://localhost:4000"
$companyA = "COMPANY-A"

# 공통 유틸 (Ticket-06 스모크에서 사용)
function New-TempJsonFile($prefix, $jsonText) {
  $path = Join-Path $env:TEMP "$($prefix)_$((Get-Date -Format 'yyyyMMddHHmmssfff')).json"
  Set-Content -Path $path -Value $jsonText -Encoding utf8
  return $path
}

function Invoke-CurlJson($method, $url, $companyId, $role, $jsonFilePath) {
  $respPath = New-TemporaryFile
  $status = & curl.exe -s -o $respPath -w "%{http_code}" `
    -X $method $url `
    -H "Content-Type: application/json" `
    -H "x-company-id: $companyId" `
    -H "x-role: $role" `
    --data "@$jsonFilePath"
  return @{ Status = $status; RespPath = $respPath }
}

function Assert-Status($actual, $expectedArray, $label, $respPath) {
  if ($expectedArray -notcontains $actual) {
    Write-Host "[FAIL][$label] 기대=$(($expectedArray -join '/')), 실제=$actual" -ForegroundColor Red
    Write-Host "응답 본문:" -ForegroundColor Yellow
    Get-Content $respPath | Write-Host
    exit 1
  }
  Write-Host "[PASS][$label] 기대 상태 코드 확인: $actual" -ForegroundColor Green
}

function Get-JsonId($respPath) {
  $json = Get-Content $respPath -Raw | ConvertFrom-Json
  if ($null -ne $json.data -and $null -ne $json.data.id) { return [int]$json.data.id }
  if ($null -ne $json.id) { return [int]$json.id }
  Write-Host "[FAIL] id를 응답에서 찾지 못했습니다." -ForegroundColor Red
  Get-Content $respPath | Write-Host
  exit 1
}

function Safe-Remove($path) {
  if (Test-Path $path) { Remove-Item $path -Force -ErrorAction SilentlyContinue }
}

# HMAC/Hash 유틸 (Ticket-08/09에서 서명 계산용)
function Sha256Hex($text) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
  ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ""
}

function HmacSha256Hex($secret, $canonical) {
  $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($secret)
  $h = New-Object System.Security.Cryptography.HMACSHA256 -ArgumentList (,$keyBytes)
  $msgBytes = [System.Text.Encoding]::UTF8.GetBytes($canonical)
  ($h.ComputeHash($msgBytes) | ForEach-Object { $_.ToString("x2") }) -join ""
}

function ConvertTo-StableJson {
  param([Parameter(Mandatory=$true)][object]$Obj)

  function Normalize($v) {
    if ($null -eq $v) { return $null }

    if ($v -is [hashtable] -or $v.PSObject.TypeNames[0] -eq 'System.Management.Automation.PSCustomObject') {
      $ht = @{}
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

function Get-LegacyCanonicalFromFile {
  param([string]$Path)
  return (node -e "const fs=require('fs'); const data=JSON.parse(fs.readFileSync(process.argv[1],'utf8')); process.stdout.write(JSON.stringify(data));" $Path).Trim()
}

# ERD gate (optional)
function Invoke-ErdGate {
  param(
    [string]$DbPath = "data/mes.db",
    [string]$OutDir = "docs/erd"
  )

  if ($env:SMOKE_GEN_ERD -ne "1") {
    return
  }

  $strict = ($env:SMOKE_GEN_ERD_STRICT -eq "1")
  $render = ($env:SMOKE_GEN_ERD_RENDER -eq "1")
  $enforce = ($env:SMOKE_GEN_ERD_ENFORCE -eq "1")

  function Erd-Fail([string]$msg) {
    if ($strict) {
      throw $msg
    } else {
      Write-Host "[ERD][WARN] $msg" -ForegroundColor Yellow
    }
  }

  try {
    if (!(Test-Path $DbPath)) {
      Erd-Fail "DB 파일이 없습니다: $DbPath"
      return
    }

    $mmdPath = Join-Path $OutDir "mes_erd.mmd"
    Write-Host "[ERD] Mermaid 생성 시작" -ForegroundColor Cyan
    & node "tools/erd/generate_erd.js" --db $DbPath --out $mmdPath | Out-Null
    if (!(Test-Path $mmdPath)) {
      Erd-Fail "Mermaid 파일 생성 실패: $mmdPath"
      return
    }
    Write-Host "[ERD] Mermaid 생성 완료: $mmdPath" -ForegroundColor Green

    if ($render) {
      Write-Host "[ERD] PNG/PDF 렌더링 시작" -ForegroundColor Cyan
      try {
        & pwsh "tools/erd/render_erd.ps1" -Input $mmdPath -OutDir $OutDir | Out-Null
        Write-Host "[ERD] PNG/PDF 렌더링 완료" -ForegroundColor Green
      } catch {
        Erd-Fail "렌더링 실패: $($_.Exception.Message)"
      }
    }

    if ($enforce) {
      $dirty = & git status --porcelain -- "$OutDir/*.mmd"
      if ($dirty) {
        throw "ERD 산출물이 git에 반영되지 않았습니다. docs/erd/*.mmd 변경사항을 커밋하세요."
      }
    }
  } catch {
    Erd-Fail "ERD 게이트 실패: $($_.Exception.Message)"
  }
}

$baseUrl = "http://localhost:4000"
$company = "SMOKE-CO"
$roleOp = "OPERATOR"
$roleViewer = "VIEWER"
$ts = Get-Random -Minimum 10000 -Maximum 99999

# 임시 JSON 파일 생성 헬퍼
function New-JsonFile($obj) {
  $tmp = New-TemporaryFile
  $json = $obj | ConvertTo-Json -Depth 4 -Compress
  Set-Content -Path $tmp -Value $json -Encoding utf8
  return $tmp
}

Write-Info "1) 품목유형 생성"
$catFile = New-JsonFile @{ name = "카테고리-$ts"; code = "CAT-$ts" }
$catResp = curl.exe -s -X POST "$baseUrl/api/v1/item-categories" `
  -H "Content-Type: application/json" `
  -H "x-company-id: $company" `
  -H "x-role: $roleOp" `
  --data-binary "@$catFile"
Assert-SuccessJson $catResp
$catId = ($catResp | ConvertFrom-Json).data.id

Write-Info "2) 품목(완제품) 생성"
$parentFile = New-JsonFile @{ categoryId = $catId; name = "완제품-$ts"; code = "ITEM-P-$ts" }
$parentResp = curl.exe -s -X POST "$baseUrl/api/v1/items" `
  -H "Content-Type: application/json" `
  -H "x-company-id: $company" `
  -H "x-role: $roleOp" `
  --data-binary "@$parentFile"
Assert-SuccessJson $parentResp
$parentId = ($parentResp | ConvertFrom-Json).data.id

Write-Info "3) 품목(자재) 생성"
$childFile = New-JsonFile @{ categoryId = $catId; name = "자재-$ts"; code = "ITEM-C-$ts" }
$childResp = curl.exe -s -X POST "$baseUrl/api/v1/items" `
  -H "Content-Type: application/json" `
  -H "x-company-id: $company" `
  -H "x-role: $roleOp" `
  --data-binary "@$childFile"
Assert-SuccessJson $childResp
$childId = ($childResp | ConvertFrom-Json).data.id

Write-Info "4) BOM 추가"
$bomFile = New-JsonFile @{ childItemId = $childId; qty = 1.5; unit = "EA" }
$bomResp = curl.exe -s -X POST "$baseUrl/api/v1/items/$parentId/parts" `
  -H "Content-Type: application/json" `
  -H "x-company-id: $company" `
  -H "x-role: $roleOp" `
  --data-binary "@$bomFile"
Assert-SuccessJson $bomResp
$bomId = ($bomResp | ConvertFrom-Json).data.id

Write-Info "5) BOM 조회"
$getResp = curl.exe -s -X GET "$baseUrl/api/v1/items/$parentId/parts" `
  -H "x-company-id: $company" `
  -H "x-role: $roleViewer"
Assert-SuccessJson $getResp

Write-Info "6) 실패 케이스 확인 (VIEWER 등록 차단)"
$failResp = curl.exe -s -X POST "$baseUrl/api/v1/items/$parentId/parts" `
  -H "Content-Type: application/json" `
  -H "x-company-id: $company" `
  -H "x-role: $roleViewer" `
  --data-binary "@$bomFile"
Assert-FailJson $failResp

Write-Host "[PASS] 스모크 테스트 완료" -ForegroundColor Green

# -----------------------------
# Ticket-04 Smoke: Processes
# -----------------------------
Write-Host "`n[SMOKE] Ticket-04 Processes 시작" -ForegroundColor Cyan

$baseUrl = "http://localhost:4000"
$companyA = "COMPANY-A"

# 1) OPERATOR로 공정 등록(201) 또는 중복(409)이면 PASS 처리
$ts = Get-Date -Format "yyyyMMddHHmmss"
$procCode = "PROC-$ts"
$procBodyPath = Join-Path $env:TEMP "smoke_process_$ts.json"

@"
{
  "name": "포장공정-$ts",
  "code": "$procCode",
  "parentId": null,
  "sortOrder": 0
}
"@ | Out-File -FilePath $procBodyPath -Encoding utf8

try {
  $respFile = Join-Path $env:TEMP "smoke_process_resp_$ts.json"

  $status = & curl.exe -s -o $respFile -w "%{http_code}" `
    -X POST "$baseUrl/api/v1/processes" `
    -H "Content-Type: application/json" `
    -H "x-company-id: $companyA" `
    -H "x-role: OPERATOR" `
    --data "@$procBodyPath"

  if ($status -ne "201" -and $status -ne "409") {
    Write-Host "[FAIL] OPERATOR 공정 등록 실패. 기대=201 또는 409, 실제=$status" -ForegroundColor Red
    Write-Host "응답 본문:" -ForegroundColor Yellow
    Get-Content $respFile | Write-Host
    exit 1
  }

  if ($status -eq "201") {
    Write-Host "[PASS] OPERATOR 공정 등록 성공(201)" -ForegroundColor Green
  } else {
    Write-Host "[PASS] OPERATOR 공정 등록 중복(409) - 허용 처리" -ForegroundColor Green
  }
}
finally {
  if (Test-Path $procBodyPath) { Remove-Item $procBodyPath -Force -ErrorAction SilentlyContinue }
}

# 2) VIEWER로 공정 등록 시 403 확인(본문은 보지 않고 코드만 확인)
$ts2 = Get-Date -Format "yyyyMMddHHmmss"
$procCode2 = "PROC-VIEWER-$ts2"
$procBodyPath2 = Join-Path $env:TEMP "smoke_process_viewer_$ts2.json"

@"
{
  "name": "뷰어차단테스트-$ts2",
  "code": "$procCode2",
  "parentId": null,
  "sortOrder": 0
}
"@ | Out-File -FilePath $procBodyPath2 -Encoding utf8

try {
  $respFile2 = Join-Path $env:TEMP "smoke_process_viewer_resp_$ts2.json"

  $status2 = & curl.exe -s -o $respFile2 -w "%{http_code}" `
    -X POST "$baseUrl/api/v1/processes" `
    -H "Content-Type: application/json" `
    -H "x-company-id: $companyA" `
    -H "x-role: VIEWER" `
    --data "@$procBodyPath2"

  if ($status2 -ne "403") {
    Write-Host "[FAIL] VIEWER 공정 등록 차단 실패. 기대=403, 실제=$status2" -ForegroundColor Red
    Write-Host "응답 본문:" -ForegroundColor Yellow
    Get-Content $respFile2 | Write-Host
    exit 1
  }

  Write-Host "[PASS] VIEWER 공정 등록 차단(403) 확인" -ForegroundColor Green
}
finally {
  if (Test-Path $procBodyPath2) { Remove-Item $procBodyPath2 -Force -ErrorAction SilentlyContinue }
}

Write-Host "[PASS] Ticket-04 Processes 스모크 완료" -ForegroundColor Green

# -----------------------------
# Ticket-05 Smoke: Equipments
# -----------------------------
Write-Host "`n[SMOKE] Ticket-05 Equipments 시작" -ForegroundColor Cyan

$baseUrl = "http://localhost:4000"
$companyA = "COMPANY-A"

# 설비 등록: 201 또는 중복 409 허용
$tsEq = Get-Date -Format "yyyyMMddHHmmss"
$eqCode = "EQ-$tsEq"
$eqBodyPath = Join-Path $env:TEMP "smoke_equipment_$tsEq.json"

@"
{
  "name": "포장기-$tsEq",
  "code": "$eqCode",
  "processId": null,
  "commType": "MODBUS_TCP",
  "commConfig": { "ip": "192.168.0.10", "port": 502, "unitId": 1 },
  "isActive": 1
}
"@ | Out-File -FilePath $eqBodyPath -Encoding utf8

try {
  $respFile = Join-Path $env:TEMP "smoke_equipment_resp_$tsEq.json"

  $status = & curl.exe -s -o $respFile -w "%{http_code}" `
    -X POST "$baseUrl/api/v1/equipments" `
    -H "Content-Type: application/json" `
    -H "x-company-id: $companyA" `
    -H "x-role: OPERATOR" `
    --data "@$eqBodyPath"

  if ($status -ne "201" -and $status -ne "409") {
    Write-Host "[FAIL] OPERATOR 설비 등록 실패. 기대=201 또는 409, 실제=$status" -ForegroundColor Red
    Write-Host "응답 본문:" -ForegroundColor Yellow
    Get-Content $respFile | Write-Host
    exit 1
  }

  if ($status -eq "201") {
    Write-Host "[PASS] OPERATOR 설비 등록 성공(201)" -ForegroundColor Green
  } else {
    Write-Host "[PASS] OPERATOR 설비 등록 중복(409) - 허용 처리" -ForegroundColor Green
  }
}
finally {
  if (Test-Path $eqBodyPath) { Remove-Item $eqBodyPath -Force -ErrorAction SilentlyContinue }
}

# VIEWER 차단: 403 확인
$tsEq2 = Get-Date -Format "yyyyMMddHHmmss"
$eqCode2 = "EQ-VIEWER-$tsEq2"
$eqBodyPath2 = Join-Path $env:TEMP "smoke_equipment_viewer_$tsEq2.json"

@"
{
  "name": "뷰어차단설비-$tsEq2",
  "code": "$eqCode2",
  "processId": null,
  "commType": "HTTP",
  "commConfig": { "url": "http://device.local/api" },
  "isActive": 1
}
"@ | Out-File -FilePath $eqBodyPath2 -Encoding utf8

try {
  $respFile2 = Join-Path $env:TEMP "smoke_equipment_viewer_resp_$tsEq2.json"

  $status2 = & curl.exe -s -o $respFile2 -w "%{http_code}" `
    -X POST "$baseUrl/api/v1/equipments" `
    -H "Content-Type: application/json" `
    -H "x-company-id: $companyA" `
    -H "x-role: VIEWER" `
    --data "@$eqBodyPath2"

  if ($status2 -ne "403") {
    Write-Host "[FAIL] VIEWER 설비 등록 차단 실패. 기대=403, 실제=$status2" -ForegroundColor Red
    Write-Host "응답 본문:" -ForegroundColor Yellow
    Get-Content $respFile2 | Write-Host
    exit 1
  }

  Write-Host "[PASS] VIEWER 설비 등록 차단(403) 확인" -ForegroundColor Green
}
finally {
  if (Test-Path $eqBodyPath2) { Remove-Item $eqBodyPath2 -Force -ErrorAction SilentlyContinue }
}

Write-Host "[PASS] Ticket-05 Equipments 스모크 완료" -ForegroundColor Green

# -----------------------------
# Ticket-06 Smoke: Defect Types (강화형 4케이스)
# -----------------------------
Write-Host "`n[SMOKE] Ticket-06 Defect Types 시작" -ForegroundColor Cyan

# (A) OPERATOR 등록: 201 또는 409 허용
$tsDef = Get-Date -Format "yyyyMMddHHmmss"
$defJson = @"
{
  "name": "스크래치-$tsDef",
  "code": "DEF-$tsDef",
  "processId": null,
  "severity": 2,
  "isActive": 1
}
"@
$defBody = New-TempJsonFile "smoke_defect" $defJson
$respA = Invoke-CurlJson "POST" "$baseUrl/api/v1/defect-types" $companyA "OPERATOR" $defBody
Assert-Status $respA.Status @("201","409") "T06-A(OPERATOR 201/409)" $respA.RespPath
Safe-Remove $defBody
Safe-Remove $respA.RespPath

# (B) VIEWER 등록: 403 확인
$tsDefB = Get-Date -Format "yyyyMMddHHmmss"
$defJsonB = @"
{
  "name": "뷰어차단불량-$tsDefB",
  "code": "DEF-VIEWER-$tsDefB",
  "processId": null,
  "severity": 1,
  "isActive": 1
}
"@
$defBodyB = New-TempJsonFile "smoke_defect_viewer" $defJsonB
$respB = Invoke-CurlJson "POST" "$baseUrl/api/v1/defect-types" $companyA "VIEWER" $defBodyB
Assert-Status $respB.Status @("403") "T06-B(VIEWER 403)" $respB.RespPath
Safe-Remove $defBodyB
Safe-Remove $respB.RespPath

# (C) 잘못된 processId(없는 값) → 400
$tsDefC = Get-Date -Format "yyyyMMddHHmmss"
$defJsonC = @"
{
  "name": "잘못된공정불량-$tsDefC",
  "code": "DEF-BADPROC-$tsDefC",
  "processId": 999999,
  "severity": 3,
  "isActive": 1
}
"@
$defBodyC = New-TempJsonFile "smoke_defect_badproc" $defJsonC
$respC = Invoke-CurlJson "POST" "$baseUrl/api/v1/defect-types" $companyA "OPERATOR" $defBodyC
Assert-Status $respC.Status @("400") "T06-C(BAD PROCESS 400)" $respC.RespPath
Safe-Remove $defBodyC
Safe-Remove $respC.RespPath

# (D) 타사 processId 사용 시 400 (교차 테넌트 차단)
Write-Host "[SMOKE][T06-D] 타사 processId 차단 테스트 시작" -ForegroundColor Cyan
$tsDefD = Get-Date -Format "yyyyMMddHHmmss"
$companyB = "COMPANY-B"

# COMPANY-B 공정 생성 → id 파싱
$procJsonB = @"
{
  "name": "타사공정-$tsDefD",
  "code": "PROC-B-$tsDefD",
  "parentId": null,
  "sortOrder": 0
}
"@
$procBodyB = New-TempJsonFile "smoke_process_companyB" $procJsonB
$respProcB = Invoke-CurlJson "POST" "$baseUrl/api/v1/processes" $companyB "OPERATOR" $procBodyB
Assert-Status $respProcB.Status @("201","409") "T06-D(PROC-B CREATE)" $respProcB.RespPath
$processIdB = Get-JsonId $respProcB.RespPath
Safe-Remove $procBodyB
Safe-Remove $respProcB.RespPath

# COMPANY-A에서 타사 processId로 등록 → 400
$defJsonD = @"
{
  "name": "타사공정불량-$tsDefD",
  "code": "DEF-XTENANT-$tsDefD",
  "processId": $processIdB,
  "severity": 2,
  "isActive": 1
}
"@
$defBodyD = New-TempJsonFile "smoke_defect_xtenant" $defJsonD
$respD = Invoke-CurlJson "POST" "$baseUrl/api/v1/defect-types" $companyA "OPERATOR" $defBodyD
Assert-Status $respD.Status @("400") "T06-D(XTENANT 400)" $respD.RespPath
Safe-Remove $defBodyD
Safe-Remove $respD.RespPath

Write-Host "[PASS] Ticket-06 Defect Types 스모크 완료" -ForegroundColor Green

# -----------------------------
# Ticket-07 Smoke: Partners (거래처)
# -----------------------------
Write-Host "`n[SMOKE] Ticket-07 Partners 시작" -ForegroundColor Cyan

if (-not $baseUrl)  { $baseUrl  = "http://localhost:4000" }
if (-not $companyA) { $companyA = "COMPANY-A" }

$ts07 = Get-Date -Format "yyyyMMddHHmmss"

function _InvokeAndGet {
  param(
    [string]$Method,
    [string]$Url,
    [string]$CompanyId,
    [string]$Role,
    [string]$JsonPath
  )
  $r = Invoke-CurlJson $Method $Url $CompanyId $Role $JsonPath
  if ($r -is [hashtable] -and $r.ContainsKey("Status") -and $r.ContainsKey("RespPath")) {
    return @{ Status = [string]$r.Status; RespPath = [string]$r.RespPath }
  }
  if ($r -is [object[]] -and $r.Length -ge 2) {
    return @{ Status = [string]$r[0]; RespPath = [string]$r[1] }
  }
  throw "Invoke-CurlJson 반환 형식을 해석할 수 없습니다."
}

# (A) OPERATOR 등록: 201 또는 409 허용
$codeA07 = "PART-$ts07"
$jsonA07 = @"
{
  "name": "거래처-$ts07",
  "code": "$codeA07",
  "type": "CUSTOMER",
  "contactName": "담당자-$ts07",
  "phone": "010-0000-0000",
  "email": "partner-$ts07@example.com",
  "address": "Seoul",
  "isActive": 1
}
"@
$pathA07 = New-TempJsonFile "t07_partner_ok_$ts07" $jsonA07
try {
  $resA07 = _InvokeAndGet "POST" "$baseUrl/api/v1/partners" $companyA "OPERATOR" $pathA07
  Assert-Status $resA07.Status @("201","409") "[T07-A] OPERATOR 등록(201/409)" $resA07.RespPath
} finally { Safe-Remove $pathA07 }

# (B) VIEWER 등록 차단: 403
$codeB07 = "PART-VIEWER-$ts07"
$jsonB07 = @"
{
  "name": "뷰어차단거래처-$ts07",
  "code": "$codeB07",
  "type": "VENDOR",
  "isActive": 1
}
"@
$pathB07 = New-TempJsonFile "t07_partner_viewer_$ts07" $jsonB07
try {
  $resB07 = _InvokeAndGet "POST" "$baseUrl/api/v1/partners" $companyA "VIEWER" $pathB07
  Assert-Status $resB07.Status @("403") "[T07-B] VIEWER 차단(403)" $resB07.RespPath
} finally { Safe-Remove $pathB07 }

# (C) 잘못된 type: 400
$codeC07 = "PART-BADTYPE-$ts07"
$jsonC07 = @"
{
  "name": "타입오류거래처-$ts07",
  "code": "$codeC07",
  "type": "UNKNOWN_TYPE",
  "isActive": 1
}
"@
$pathC07 = New-TempJsonFile "t07_partner_badtype_$ts07" $jsonC07
try {
  $resC07 = _InvokeAndGet "POST" "$baseUrl/api/v1/partners" $companyA "OPERATOR" $pathC07
  Assert-Status $resC07.Status @("400") "[T07-C] 잘못된 type(400)" $resC07.RespPath
} finally { Safe-Remove $pathC07 }

Write-Host "[PASS] Ticket-07 Partners 스모크 완료" -ForegroundColor Green

# -----------------------------
# Ticket-08 Smoke: Telemetry (최소 수신 API)
# -----------------------------
Write-Host "`n[SMOKE] Ticket-08 Telemetry 시작" -ForegroundColor Cyan

if (-not $baseUrl)  { $baseUrl  = "http://localhost:4000" }
if (-not $companyA) { $companyA = "COMPANY-A" }
$companyB = "COMPANY-B"

$ts08 = Get-Date -Format "yyyyMMddHHmmss"

function _InvokeAndGet {
  param([string]$Method,[string]$Url,[string]$CompanyId,[string]$Role,[string]$JsonPath,[hashtable]$ExtraHeaders)
  if ($ExtraHeaders) {
    $respFile = New-TemporaryFile
    $args = @("-s","-o",$respFile,"-w","%{http_code}","-X",$Method,$Url,
              "-H","Content-Type: application/json",
              "-H","x-company-id: $CompanyId",
              "-H","x-role: $Role")
    foreach ($k in $ExtraHeaders.Keys) {
      $args += @("-H", "${k}: $($ExtraHeaders[$k])")
    }
    if ($JsonPath) { $args += @("--data", "@$JsonPath") }
    $status = & curl.exe @args
    return @{ Status = [string]$status; RespPath = [string]$respFile }
  }

  $r = Invoke-CurlJson $Method $Url $CompanyId $Role $JsonPath
  if ($r -is [hashtable] -and $r.ContainsKey("Status") -and $r.ContainsKey("RespPath")) {
    return @{ Status = [string]$r.Status; RespPath = [string]$r.RespPath }
  }
  if ($r -is [object[]] -and $r.Length -ge 2) {
    return @{ Status = [string]$r[0]; RespPath = [string]$r[1] }
  }
  throw "Invoke-CurlJson 반환 형식을 해석할 수 없습니다."
}

# ---- COMPANY-A용 공정/설비 생성 ----
$procCodeA = "PROC-A-T08-$ts08"
$procBodyA = @"
{ "name":"T08공정-$ts08", "code":"$procCodeA", "parentId": null, "sortOrder": 0 }
"@
$procPathA = New-TempJsonFile "t08_procA_$ts08" $procBodyA
$processIdA = $null
try {
  $resPA = _InvokeAndGet "POST" "$baseUrl/api/v1/processes" $companyA "OPERATOR" $procPathA
  Assert-Status $resPA.Status @("201") "[T08-SETUP-A] COMPANY-A 공정 생성(201)" $resPA.RespPath
  $processIdA = Get-JsonId $resPA.RespPath
} finally { Safe-Remove $procPathA }

$equipCodeA = "EQ-A-T08-$ts08"
$equipBodyA = @"
{
  "name": "T08설비A-$ts08",
  "code": "$equipCodeA",
  "processId": $processIdA,
  "commType": "HTTP",
  "commConfig": { "url": "http://dummy" },
  "isActive": 1
}
"@
$equipPathA = New-TempJsonFile "t08_equipA_$ts08" $equipBodyA
try {
  $resEA = _InvokeAndGet "POST" "$baseUrl/api/v1/equipments" $companyA "OPERATOR" $equipPathA
  Assert-Status $resEA.Status @("201","409") "[T08-SETUP-B] COMPANY-A 설비 생성(201/409)" $resEA.RespPath
} finally { Safe-Remove $equipPathA }
$equipIdA = Get-JsonId $resEA.RespPath

# device-key 발급
$issueBodyA = @"
{ "note": "t08-issue-$ts08" }
"@
$issuePathA = New-TempJsonFile "t08_issueA_$ts08" $issueBodyA
$resIssueA = _InvokeAndGet "POST" "$baseUrl/api/v1/equipments/$equipIdA/device-key" $companyA "MANAGER" $issuePathA
Assert-Status $resIssueA.Status @("201") "[T08-SETUP-C] COMPANY-A device-key 발급(201)" $resIssueA.RespPath
Safe-Remove $issuePathA
$issueJsonA = Get-Content $resIssueA.RespPath -Raw | ConvertFrom-Json
$deviceKeyIdA = $issueJsonA.data.deviceKeyId
$deviceSecretA = $issueJsonA.data.deviceSecret

function BuildTeleHeadersT08($bodyPath) {
  $bodyRaw = Get-Content $bodyPath -Raw
  $bodyCanonical = Get-LegacyCanonicalFromFile $bodyPath
  $nonce = ([Guid]::NewGuid().ToString("N"))
  $tsNow = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $bodyHash = Sha256Hex $bodyCanonical
  $canonical = "$companyA`n$deviceKeyIdA`n$tsNow`n$nonce`n$bodyHash"
  $sig = HmacSha256Hex $deviceSecretA $canonical
  if ($env:SMOKE_DEBUG_TELEMETRY -eq "1") {
    Write-Host "[DEBUG][T08] canonical=$canonical" -ForegroundColor Yellow
    Write-Host "[DEBUG][T08] sigCalc=$sig" -ForegroundColor Yellow
  }
  return @{
    "x-device-key" = $deviceKeyIdA
    "x-ts" = "$tsNow"
    "x-nonce" = $nonce
    "x-signature" = $sig
    "x-canonical" = "legacy-json"
  }
}

# (A) 정상 Telemetry 수신 201
$teleBodyOk = @"
{
  "equipmentCode": "$equipCodeA",
  "timestamp": "$(Get-Date -Format o)",
  "eventType": "STATUS",
  "payload": { "state": "RUN", "speed": 123 }
}
"@
$telePathOk = New-TempJsonFile "t08_tel_ok_$ts08" $teleBodyOk
$rawOk = Get-Content $telePathOk -Raw
if ($env:SMOKE_DEBUG_TELEMETRY -eq "1") {
  Write-Host "[DEBUG][T08] client raw body:" -ForegroundColor Yellow
  Write-Host $rawOk -ForegroundColor Yellow
}
$headersOk = BuildTeleHeadersT08 $telePathOk
try {
  $resT1 = _InvokeAndGet "POST" "$baseUrl/api/v1/telemetry/events" $companyA "VIEWER" $telePathOk $headersOk
  Assert-Status $resT1.Status @("201") "[T08-A] 정상 수신(201)" $resT1.RespPath
} finally { Safe-Remove $telePathOk }

# (B) equipmentCode 누락 400
$teleBodyMissing = @"
{
  "timestamp": "$(Get-Date -Format o)",
  "eventType": "STATUS",
  "payload": { "state": "RUN" }
}
"@
$telePathMissing = New-TempJsonFile "t08_tel_missing_$ts08" $teleBodyMissing
$headersMissing = BuildTeleHeadersT08 $telePathMissing
try {
  $resT2 = _InvokeAndGet "POST" "$baseUrl/api/v1/telemetry/events" $companyA "VIEWER" $telePathMissing $headersMissing
  Assert-Status $resT2.Status @("400") "[T08-B] equipmentCode 누락(400)" $resT2.RespPath
} finally { Safe-Remove $telePathMissing }

# (C) 타사 equipmentCode 400
$procCodeB = "PROC-B-T08-$ts08"
$procBodyB = @"
{ "name":"T08공정B-$ts08", "code":"$procCodeB", "parentId": null, "sortOrder": 0 }
"@
$procPathB = New-TempJsonFile "t08_procB_$ts08" $procBodyB
$processIdB = $null
try {
  $resPB = _InvokeAndGet "POST" "$baseUrl/api/v1/processes" $companyB "OPERATOR" $procPathB
  Assert-Status $resPB.Status @("201") "[T08-SETUP-C] COMPANY-B 공정 생성(201)" $resPB.RespPath
  $processIdB = Get-JsonId $resPB.RespPath
} finally { Safe-Remove $procPathB }

$equipCodeB = "EQ-B-T08-$ts08"
$equipBodyB = @"
{
  "name": "T08설비B-$ts08",
  "code": "$equipCodeB",
  "processId": $processIdB,
  "commType": "HTTP",
  "commConfig": { "url": "http://dummy" },
  "isActive": 1
}
"@
$equipPathB = New-TempJsonFile "t08_equipB_$ts08" $equipBodyB
try {
  $resEB = _InvokeAndGet "POST" "$baseUrl/api/v1/equipments" $companyB "OPERATOR" $equipPathB
  Assert-Status $resEB.Status @("201","409") "[T08-SETUP-D] COMPANY-B 설비 생성(201/409)" $resEB.RespPath
} finally { Safe-Remove $equipPathB }

$teleBodyCross = @"
{
  "equipmentCode": "$equipCodeB",
  "timestamp": "$(Get-Date -Format o)",
  "eventType": "STATUS",
  "payload": { "state": "RUN" }
}
"@
$telePathCross = New-TempJsonFile "t08_tel_cross_$ts08" $teleBodyCross
$headersCross = BuildTeleHeadersT08 $telePathCross
try {
  $resT3 = _InvokeAndGet "POST" "$baseUrl/api/v1/telemetry/events" $companyA "VIEWER" $telePathCross $headersCross
  Assert-Status $resT3.Status @("400") "[T08-C] 타사 equipmentCode 차단(400)" $resT3.RespPath
} finally { Safe-Remove $telePathCross }

Write-Host "[PASS] Ticket-08 Telemetry 스모크 완료" -ForegroundColor Green

# -----------------------------
# Ticket-09 Smoke: Telemetry Auth
# -----------------------------
Write-Host "`n[SMOKE] Ticket-09 Telemetry Auth 시작" -ForegroundColor Cyan

if (-not $baseUrl)  { $baseUrl  = "http://localhost:4000" }
if (-not $companyA) { $companyA = "COMPANY-A" }
$companyB = "COMPANY-B"

$ts09 = Get-Date -Format "yyyyMMddHHmmss"

function Invoke-CurlJsonAuth {
  param([string]$Method,[string]$Url,[string]$CompanyId,[string]$Role,[string]$JsonPath,[hashtable]$ExtraHeaders)
  $respFile = Join-Path $env:TEMP ("smoke_t09_" + [Guid]::NewGuid().ToString("N") + ".json")
  $args = @("-s","-o",$respFile,"-w","%{http_code}","-X",$Method,$Url,
            "-H","Content-Type: application/json",
            "-H","x-company-id: $CompanyId",
            "-H","x-role: $Role")
  foreach ($k in $ExtraHeaders.Keys) {
    $args += @("-H", "${k}: $($ExtraHeaders[$k])")
  }
  if ($JsonPath) { $args += @("--data", "@$JsonPath") }
  $status = & curl.exe @args
  return @{ Status = [string]$status; RespFile = [string]$respFile }
}

function Sha256HexStr([string]$s) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($s)
  ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ""
}

function HmacSha256HexStr([string]$secret, [string]$canonical) {
  $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($secret)
  $h = New-Object System.Security.Cryptography.HMACSHA256 -ArgumentList (,$keyBytes)
  $msgBytes = [System.Text.Encoding]::UTF8.GetBytes($canonical)
  ($h.ComputeHash($msgBytes) | ForEach-Object { $_.ToString("x2") }) -join ""
}

# 준비: COMPANY-A 공정/설비 생성
$procBodyA9 = @"
{ "name":"T09공정A-$ts09", "code":"PROC-A-T09-$ts09", "parentId": null, "sortOrder": 0 }
"@
$procPathA9 = New-TempJsonFile "t09_procA_$ts09" $procBodyA9
$procResA9 = Invoke-CurlJsonAuth "POST" "$baseUrl/api/v1/processes" $companyA "OPERATOR" $procPathA9 @{}
Assert-Status $procResA9.Status @("201") "[T09-SETUP-A] COMPANY-A 공정 생성(201)" $procResA9.RespFile
$processIdA9 = Get-JsonId $procResA9.RespFile

$equipCodeA9 = "EQ-A-T09-$ts09"
$equipBodyA9 = @"
{
  "name": "T09설비A-$ts09",
  "code": "$equipCodeA9",
  "processId": $processIdA9,
  "commType": "HTTP",
  "commConfig": { "url": "http://dummy" },
  "isActive": 1
}
"@
$equipPathA9 = New-TempJsonFile "t09_equipA_$ts09" $equipBodyA9
$equipResA9 = Invoke-CurlJsonAuth "POST" "$baseUrl/api/v1/equipments" $companyA "OPERATOR" $equipPathA9 @{}
Assert-Status $equipResA9.Status @("201") "[T09-SETUP-B] COMPANY-A 설비 생성(201)" $equipResA9.RespFile
$equipmentIdA9 = Get-JsonId $equipResA9.RespFile

# (1) device-key 발급
$issueBody9 = @"
{ "note": "smoke-issue-$ts09" }
"@
$issuePath9 = New-TempJsonFile "t09_issue_$ts09" $issueBody9
$issueRes9 = Invoke-CurlJsonAuth "POST" "$baseUrl/api/v1/equipments/$equipmentIdA9/device-key" $companyA "MANAGER" $issuePath9 @{}
Assert-Status $issueRes9.Status @("201") "[T09-1] device-key 발급(201)" $issueRes9.RespFile
$issueJson9 = Get-Content $issueRes9.RespFile -Raw | ConvertFrom-Json
$deviceKeyId9 = $issueJson9.data.deviceKeyId
$deviceSecret9 = $issueJson9.data.deviceSecret
if (-not $deviceKeyId9 -or -not $deviceSecret9) {
  Write-Host "[FAIL] deviceKeyId/deviceSecret 파싱 실패" -ForegroundColor Red
  Get-Content $issueRes9.RespFile | Write-Host
  exit 1
}

# (2) 정상 telemetry 201
$teleBody9 = @"
{
  "equipmentCode": "$equipCodeA9",
  "eventType": "STATUS",
  "payload": { "state": "RUN", "speed": 77 }
}
"@
$telePath9 = New-TempJsonFile "t09_tel_ok_$ts09" $teleBody9
$teleRaw9 = Get-Content $telePath9 -Raw
$teleCanonical9 = Get-LegacyCanonicalFromFile $telePath9
$nonce9 = ([Guid]::NewGuid().ToString("N"))
$tsEpoch9 = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$bodyHash9 = Sha256HexStr $teleCanonical9
$canonical9 = "$companyA`n$deviceKeyId9`n$tsEpoch9`n$nonce9`n$bodyHash9"
$signature9 = HmacSha256HexStr $deviceSecret9 $canonical9

$authHeaders9 = @{
  "x-device-key" = $deviceKeyId9
  "x-ts" = "$tsEpoch9"
  "x-nonce" = $nonce9
  "x-signature" = $signature9
  "x-canonical" = "legacy-json"
}

$resT9Ok = Invoke-CurlJsonAuth "POST" "$baseUrl/api/v1/telemetry/events" $companyA "VIEWER" $telePath9 $authHeaders9
Assert-Status $resT9Ok.Status @("201") "[T09-2] 정상 telemetry(201)" $resT9Ok.RespFile

# (3) nonce 재전송 401
$resT9Replay = Invoke-CurlJsonAuth "POST" "$baseUrl/api/v1/telemetry/events" $companyA "VIEWER" $telePath9 $authHeaders9
Assert-Status $resT9Replay.Status @("401") "[T09-3] nonce 재전송 차단(401)" $resT9Replay.RespFile

# (4) 서명 변조 401
$authHeadersBad9 = @{
  "x-device-key" = $deviceKeyId9
  "x-ts" = "$tsEpoch9"
  "x-nonce" = ([Guid]::NewGuid().ToString("N"))
  "x-signature" = ("00" + $signature9.Substring(2))
}
$resT9Bad = Invoke-CurlJsonAuth "POST" "$baseUrl/api/v1/telemetry/events" $companyA "VIEWER" $telePath9 $authHeadersBad9
Assert-Status $resT9Bad.Status @("401") "[T09-4] 서명 변조 차단(401)" $resT9Bad.RespFile

Write-Host "[PASS] Ticket-09 Telemetry Auth 스모크 완료" -ForegroundColor Green

# -----------------------------
# Ticket-09.1 Smoke: Telemetry Ops (rotate/revoke/nonce cleanup)
# -----------------------------
Write-Host "`n[SMOKE] Ticket-09.1 Telemetry Ops 시작" -ForegroundColor Cyan

if (-not $baseUrl)  { $baseUrl  = "http://localhost:4000" }
if (-not $companyA) { $companyA = "COMPANY-A" }

function Send-TelemetrySigned {
  param(
    [string]$CompanyId,
    [string]$DeviceKeyId,
    [string]$DeviceSecret,
    [string]$EquipmentCode,
    [int[]]$Expected
  )

  $bodyObj = @{
    equipmentCode = $EquipmentCode
    eventType = "STATUS"
    payload = @{ state = "RUN"; speed = 10 }
  }
  $tmp = New-TempJsonFile "t09_1_tel" ($bodyObj | ConvertTo-Json -Depth 10 -Compress)
  $bodyCanonical = Get-LegacyCanonicalFromFile $tmp
  $bodyHash = Sha256HexStr $bodyCanonical
  $tsEpoch = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $nonce = ([Guid]::NewGuid().ToString("N"))
  $canonical = "$CompanyId`n$DeviceKeyId`n$tsEpoch`n$nonce`n$bodyHash"
  $signature = HmacSha256HexStr $DeviceSecret $canonical

  $resp = Invoke-CurlJsonAuth "POST" "$baseUrl/api/v1/telemetry/events" $CompanyId "VIEWER" $tmp @{
    "x-device-key" = $DeviceKeyId
    "x-ts" = "$tsEpoch"
    "x-nonce" = $nonce
    "x-signature" = $signature
    "x-canonical" = "legacy-json"
  }
  Assert-Status $resp.Status $Expected "[T09.1] telemetry signed" $resp.RespFile
}

function Send-TelemetrySignedStableJson {
  param(
    [string]$CompanyId,
    [string]$DeviceKeyId,
    [string]$DeviceKeySecret,
    [string]$EquipmentCode,
    [int[]]$Expected
  )

  # 키 순서를 섞은 payload (stable-json 규칙 검증)
  $bodyObj = @{
    payload = @{ z = 9; a = 1; t = (Get-Date).ToString("o") }
    eventType = "TELEMETRY"
    equipmentCode = $EquipmentCode
  }
  $rawFile = New-TempJsonFile "t09_2_body" ($bodyObj | ConvertTo-Json -Depth 10 -Compress)
  $bodyCanonical = (node -e "const fs=require('fs'); const {stableStringify}=require('./src/utils/canonicalJson'); const data=JSON.parse(fs.readFileSync(process.argv[1],'utf8')); process.stdout.write(stableStringify(data));" $rawFile).Trim()
  $bodyHash = Sha256HexStr $bodyCanonical
  $tsEpoch = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $nonce = ([Guid]::NewGuid().ToString("N"))
  $canonical = "$CompanyId`n$DeviceKeyId`n$tsEpoch`n$nonce`n$bodyHash"
  $signature = node -e "const crypto=require('crypto'); const secret=process.argv[1]; const canonical=process.argv[2]; process.stdout.write(crypto.createHmac('sha256',secret).update(canonical,'utf8').digest('hex'));" $DeviceKeySecret $canonical

  if ($env:SMOKE_DEBUG_TELEMETRY -eq "1") {
    Write-Host "[DEBUG][T09.2] canonical=$canonical" -ForegroundColor Yellow
    Write-Host "[DEBUG][T09.2] bodyHash=$bodyHash" -ForegroundColor Yellow
  }

  $resp = Invoke-CurlJsonAuth "POST" "$baseUrl/api/v1/telemetry/events" $CompanyId "VIEWER" $rawFile @{
    "x-device-key" = $DeviceKeyId
    "x-ts" = "$tsEpoch"
    "x-nonce" = $nonce
    "x-signature" = $signature
    "x-canonical" = "stable-json"
  }
  Assert-Status $resp.Status $Expected "[T09.2] telemetry stable-json" $resp.RespFile
}

# 1) rotate: 새 키 201, 이전 키 401
$rotateRes1 = Invoke-CurlJsonAuth "POST" "$baseUrl/api/v1/equipments/$equipmentIdA9/device-key/rotate" $companyA "OPERATOR" $null @{}
Assert-Status $rotateRes1.Status @("200","201") "[T09.1-1] device-key rotate(1)" $rotateRes1.RespFile
$rotateJson1 = Get-Content $rotateRes1.RespFile -Raw | ConvertFrom-Json
$newKeyId1 = $rotateJson1.data.deviceKeyId
$newSecret1 = $rotateJson1.data.deviceKeySecret

Send-TelemetrySigned -CompanyId $companyA -DeviceKeyId $newKeyId1 -DeviceSecret $newSecret1 -EquipmentCode $equipCodeA9 -Expected @(201)
Write-Host "[PASS] Ticket-09.1 rotate(1) 새 키 201 확인" -ForegroundColor Green

$oldKeyId = $newKeyId1
$oldSecret = $newSecret1
$rotateRes2 = Invoke-CurlJsonAuth "POST" "$baseUrl/api/v1/equipments/$equipmentIdA9/device-key/rotate" $companyA "OPERATOR" $null @{}
Assert-Status $rotateRes2.Status @("200","201") "[T09.1-2] device-key rotate(2)" $rotateRes2.RespFile
$rotateJson2 = Get-Content $rotateRes2.RespFile -Raw | ConvertFrom-Json
$newKeyId2 = $rotateJson2.data.deviceKeyId
$newSecret2 = $rotateJson2.data.deviceKeySecret

Send-TelemetrySigned -CompanyId $companyA -DeviceKeyId $oldKeyId -DeviceSecret $oldSecret -EquipmentCode $equipCodeA9 -Expected @(401)
Send-TelemetrySigned -CompanyId $companyA -DeviceKeyId $newKeyId2 -DeviceSecret $newSecret2 -EquipmentCode $equipCodeA9 -Expected @(201)
Write-Host "[PASS] Ticket-09.1 rotate(2) 이전키 401 / 새키 201 확인" -ForegroundColor Green

# 09.2 stable-json canonical 확인 (201)
Send-TelemetrySignedStableJson -CompanyId $companyA -DeviceKeyId $newKeyId2 -DeviceKeySecret $newSecret2 -EquipmentCode $equipCodeA9 -Expected @(201)
Write-Host "[PASS] Ticket-09.2 stable-json canonical 확인(201)" -ForegroundColor Green

# 2) revoke: 폐기 후 401
$revokeRes = Invoke-CurlJsonAuth "POST" "$baseUrl/api/v1/equipments/$equipmentIdA9/device-key/revoke" $companyA "OPERATOR" $null @{}
Assert-Status $revokeRes.Status @("200") "[T09.1-3] device-key revoke" $revokeRes.RespFile
Send-TelemetrySigned -CompanyId $companyA -DeviceKeyId $newKeyId2 -DeviceSecret $newSecret2 -EquipmentCode $equipCodeA9 -Expected @(401)
Write-Host "[PASS] Ticket-09.1 revoke 후 401 확인" -ForegroundColor Green

# 3) nonce cleanup: 오래된 nonce 삭제 확인 (node helper 사용)
$cleanupJson = node -e "const {db,cleanupNonces,countNonces}=require('./src/db'); const eq=Number(process.argv[1]); const now=Math.floor(Date.now()/1000); db.prepare('INSERT INTO telemetry_nonces (company_id,equipment_id,nonce,ts,created_at) VALUES (?,?,?,?,?)').run('COMPANY-A', eq, 'SMOKE-NONCE-'+now, now-999999, new Date().toISOString()); const before=countNonces(); const removed=cleanupNonces(now-10); const after=countNonces(); console.log(JSON.stringify({before,removed,after}));" $equipmentIdA9
$cleanup = $cleanupJson | ConvertFrom-Json
if ($cleanup.removed -lt 1) {
  Write-Host "[FAIL] Ticket-09.1 nonce cleanup 삭제 건수 부족" -ForegroundColor Red
  Write-Host $cleanupJson
  exit 1
}
Write-Host "[PASS] Ticket-09.1 nonce cleanup 삭제 확인" -ForegroundColor Green

Write-Host "[PASS] Ticket-09.1 Telemetry Ops 스모크 완료" -ForegroundColor Green

# -----------------------------
# Ticket-10 Smoke: Work Orders / Results
# -----------------------------
Write-Host "`n[SMOKE] Ticket-10 Work Orders/Results 시작" -ForegroundColor Cyan

if (-not $baseUrl)  { $baseUrl  = "http://localhost:4000" }
if (-not $companyA) { $companyA = "COMPANY-A" }
$companyB = "COMPANY-B"

function New-JsonFileFromObj {
  param([object]$Obj)
  $json = $Obj | ConvertTo-Json -Depth 10 -Compress
  return New-TempJsonFile "t10" $json
}

function Invoke-ApiSimple {
  param(
    [string]$Method,
    [string]$Url,
    [hashtable]$Headers,
    [string]$JsonFilePath
  )
  $respPath = New-TemporaryFile
  $args = @("-s","-o",$respPath,"-w","%{http_code}","-X",$Method,$Url)
  foreach ($k in $Headers.Keys) {
    $args += @("-H", "${k}: $($Headers[$k])")
  }
  if ($JsonFilePath) {
    $args += @("-H","Content-Type: application/json","--data","@$JsonFilePath")
  }
  $status = & curl.exe @args
  return @{ Status = [string]$status; RespPath = [string]$respPath }
}

function Ensure-Item {
  param([string]$CompanyId, [string]$Code)
  $catList = Invoke-ApiSimple "GET" "$baseUrl/api/v1/item-categories" @{ "x-company-id"=$CompanyId; "x-role"="VIEWER" } $null
  Assert-Status $catList.Status @("200") "T10 category list" $catList.RespPath
  $cat = (Get-Content $catList.RespPath -Raw | ConvertFrom-Json).data | Select-Object -First 1
  if (-not $cat) {
    $catFile = New-JsonFileFromObj @{ name="SMOKE_CAT"; code="SMOKE-CAT" }
    $catRes = Invoke-ApiSimple "POST" "$baseUrl/api/v1/item-categories" @{ "x-company-id"=$CompanyId; "x-role"="OPERATOR" } $catFile
    Assert-Status $catRes.Status @("201","409") "T10 category create" $catRes.RespPath
  }
  $catList2 = Invoke-ApiSimple "GET" "$baseUrl/api/v1/item-categories" @{ "x-company-id"=$CompanyId; "x-role"="VIEWER" } $null
  $cat2 = (Get-Content $catList2.RespPath -Raw | ConvertFrom-Json).data | Select-Object -First 1

  $itemFile = New-JsonFileFromObj @{ categoryId=$cat2.id; name="SMOKE_ITEM_$Code"; code=$Code }
  $itemRes = Invoke-ApiSimple "POST" "$baseUrl/api/v1/items" @{ "x-company-id"=$CompanyId; "x-role"="OPERATOR" } $itemFile
  Assert-Status $itemRes.Status @("201","409") "T10 item create" $itemRes.RespPath

  $itemList = Invoke-ApiSimple "GET" "$baseUrl/api/v1/items" @{ "x-company-id"=$CompanyId; "x-role"="VIEWER" } $null
  $item = (Get-Content $itemList.RespPath -Raw | ConvertFrom-Json).data | Where-Object { $_.code -eq $Code } | Select-Object -First 1
  if (-not $item) { Write-Host "[FAIL] item not found" -ForegroundColor Red; exit 1 }
  return $item.id
}

function Ensure-Process {
  param([string]$CompanyId, [string]$ProcCode)
  $procFile = New-JsonFileFromObj @{ name="SMOKE_PROC_$ProcCode"; code=$ProcCode; sortOrder=0 }
  $procRes = Invoke-ApiSimple "POST" "$baseUrl/api/v1/processes" @{ "x-company-id"=$CompanyId; "x-role"="OPERATOR" } $procFile
  Assert-Status $procRes.Status @("201","409") "T10 process create" $procRes.RespPath
  $procList = Invoke-ApiSimple "GET" "$baseUrl/api/v1/processes" @{ "x-company-id"=$CompanyId; "x-role"="VIEWER" } $null
  $proc = (Get-Content $procList.RespPath -Raw | ConvertFrom-Json).data | Where-Object { $_.code -eq $ProcCode } | Select-Object -First 1
  if (-not $proc) { Write-Host "[FAIL] process not found" -ForegroundColor Red; exit 1 }
  return $proc.id
}

function Ensure-Equipment {
  param([string]$CompanyId, [string]$EqCode, [int]$ProcessId)
  $eqFile = New-JsonFileFromObj @{
    name="SMOKE_EQ_$EqCode"; code=$EqCode; processId=$ProcessId;
    commType="SERIAL"; commConfig=@{ port="COM1"; baudrate=9600; intervalSec=1 }; isActive=1
  }
  $eqRes = Invoke-ApiSimple "POST" "$baseUrl/api/v1/equipments" @{ "x-company-id"=$CompanyId; "x-role"="OPERATOR" } $eqFile
  Assert-Status $eqRes.Status @("201","409") "T10 equipment create" $eqRes.RespPath
  $eqList = Invoke-ApiSimple "GET" "$baseUrl/api/v1/equipments" @{ "x-company-id"=$CompanyId; "x-role"="VIEWER" } $null
  $eq = (Get-Content $eqList.RespPath -Raw | ConvertFrom-Json).data | Where-Object { $_.code -eq $EqCode } | Select-Object -First 1
  if (-not $eq) { Write-Host "[FAIL] equipment not found" -ForegroundColor Red; exit 1 }
  return $eq.id
}

Write-Host "[STEP] Ticket-10 준비: COMPANY-A 기준 item/process/equipment 확보" -ForegroundColor Cyan
$itemA = Ensure-Item -CompanyId $companyA -Code "SMOKE-ITEM-A10"
$procA = Ensure-Process -CompanyId $companyA -ProcCode "SMOKE-PROC-A10"
$eqA = Ensure-Equipment -CompanyId $companyA -EqCode "SMOKE-EQ-A10" -ProcessId $procA

Write-Host "[STEP] Ticket-10 작업지시 등록 201/409" -ForegroundColor Cyan
$woNo = "WO-SMOKE-" + (Get-Date -Format "yyyyMMddHHmmss")
$woFile = New-JsonFileFromObj @{
  woNo = $woNo; itemId = $itemA; processId = $procA; equipmentId = $eqA;
  planQty = 10; status = "PLANNED"
}
$woResp = Invoke-ApiSimple "POST" "$baseUrl/api/v1/work-orders" @{ "x-company-id"=$companyA; "x-role"="OPERATOR" } $woFile
Assert-Status $woResp.Status @("201","409") "T10 work-order create" $woResp.RespPath
$woId = $null
if ($woResp.Status -eq "201") {
  $woId = Get-JsonId $woResp.RespPath
}

Write-Host "[STEP] Ticket-10 VIEWER 작업지시 등록 차단 403" -ForegroundColor Cyan
$woFile2 = New-JsonFileFromObj @{ woNo="WO-SMOKE-VIEW"; itemId=$itemA; processId=$procA; planQty=1; status="PLANNED" }
$woResp2 = Invoke-ApiSimple "POST" "$baseUrl/api/v1/work-orders" @{ "x-company-id"=$companyA; "x-role"="VIEWER" } $woFile2
Assert-Status $woResp2.Status @("403") "T10 work-order viewer" $woResp2.RespPath

Write-Host "[STEP] Ticket-10 타사 item/process 조합 400" -ForegroundColor Cyan
$itemB = Ensure-Item -CompanyId $companyB -Code "SMOKE-ITEM-B10"
$badFile = New-JsonFileFromObj @{ woNo="WO-SMOKE-BAD"; itemId=$itemB; processId=$procA; planQty=1; status="PLANNED" }
$badResp = Invoke-ApiSimple "POST" "$baseUrl/api/v1/work-orders" @{ "x-company-id"=$companyA; "x-role"="OPERATOR" } $badFile
Assert-Status $badResp.Status @("400") "T10 work-order cross-tenant" $badResp.RespPath

Write-Host "[STEP] Ticket-10 실적 등록 201" -ForegroundColor Cyan
if (-not $woId) {
  $woList = Invoke-ApiSimple "GET" "$baseUrl/api/v1/work-orders?limit=200" @{ "x-company-id"=$companyA; "x-role"="VIEWER" } $null
  Assert-Status $woList.Status @("200") "T10 work-order list" $woList.RespPath
  $wo = (Get-Content $woList.RespPath -Raw | ConvertFrom-Json).data | Where-Object { $_.woNo -eq $woNo } | Select-Object -First 1
  if (-not $wo) { Write-Host "[FAIL] work-order not found for results" -ForegroundColor Red; exit 1 }
  $woId = $wo.id
}

$resFile = New-JsonFileFromObj @{ goodQty=5; defectQty=1; eventTs=(Get-Date).ToString("o"); note="smoke" }
$resResp = Invoke-ApiSimple "POST" "$baseUrl/api/v1/work-orders/$woId/results" @{ "x-company-id"=$companyA; "x-role"="OPERATOR" } $resFile
Assert-Status $resResp.Status @("201") "T10 results create" $resResp.RespPath

Write-Host "[PASS] Ticket-10 Work Orders/Results 스모크 완료" -ForegroundColor Green

# -----------------------------
# Ticket-11 Smoke: Quality Inspections / Defects
# -----------------------------
Write-Host "`n[SMOKE] Ticket-11 Quality Inspections 시작" -ForegroundColor Cyan

function T11_EnsureInspectionPrereqs {
  param([string]$CompanyId)

  $procCode = "SMOKE-Q-PROC"
  $eqCode = "SMOKE-Q-EQ"
  $defCode = "SMOKE-Q-DEF"

  $pfile = New-JsonFileFromObj @{ name="SMOKE_Q_PROC"; code=$procCode; sortOrder=0 }
  $pr = Invoke-ApiSimple "POST" "$baseUrl/api/v1/processes" @{ "x-company-id"=$CompanyId; "x-role"="OPERATOR" } $pfile
  Assert-Status $pr.Status @("201","409") "T11 process ensure" $pr.RespPath

  $plist = Invoke-ApiSimple "GET" "$baseUrl/api/v1/processes" @{ "x-company-id"=$CompanyId; "x-role"="VIEWER" } $null
  Assert-Status $plist.Status @("200") "T11 process list" $plist.RespPath
  $proc = (Get-Content $plist.RespPath -Raw | ConvertFrom-Json).data | Where-Object { $_.code -eq $procCode } | Select-Object -First 1
  if (-not $proc) { Write-Host "[FAIL] T11 process not found" -ForegroundColor Red; exit 1 }

  $efile = New-JsonFileFromObj @{
    name="SMOKE_Q_EQ"; code=$eqCode; processId=$proc.id;
    commType="SERIAL"; commConfig=@{ port="COM1"; baudrate=9600; intervalSec=1 }; isActive=1
  }
  $er = Invoke-ApiSimple "POST" "$baseUrl/api/v1/equipments" @{ "x-company-id"=$CompanyId; "x-role"="OPERATOR" } $efile
  Assert-Status $er.Status @("201","409") "T11 equipment ensure" $er.RespPath

  $elist = Invoke-ApiSimple "GET" "$baseUrl/api/v1/equipments" @{ "x-company-id"=$CompanyId; "x-role"="VIEWER" } $null
  Assert-Status $elist.Status @("200") "T11 equipment list" $elist.RespPath
  $eq = (Get-Content $elist.RespPath -Raw | ConvertFrom-Json).data | Where-Object { $_.code -eq $eqCode } | Select-Object -First 1
  if (-not $eq) { Write-Host "[FAIL] T11 equipment not found" -ForegroundColor Red; exit 1 }

  $dfile = New-JsonFileFromObj @{ name="SMOKE_Q_DEF"; code=$defCode; processId=$proc.id }
  $dr = Invoke-ApiSimple "POST" "$baseUrl/api/v1/defect-types" @{ "x-company-id"=$CompanyId; "x-role"="OPERATOR" } $dfile
  Assert-Status $dr.Status @("201","409") "T11 defect-type ensure" $dr.RespPath

  $dlist = Invoke-ApiSimple "GET" "$baseUrl/api/v1/defect-types" @{ "x-company-id"=$CompanyId; "x-role"="VIEWER" } $null
  Assert-Status $dlist.Status @("200") "T11 defect-type list" $dlist.RespPath
  $def = (Get-Content $dlist.RespPath -Raw | ConvertFrom-Json).data | Where-Object { $_.code -eq $defCode } | Select-Object -First 1
  if (-not $def) { Write-Host "[FAIL] T11 defect-type not found" -ForegroundColor Red; exit 1 }

  return @{
    processId = $proc.id
    equipmentId = $eq.id
    defectTypeId = $def.id
  }
}

function T11_CreateInspection {
  param([string]$CompanyId, [string]$Role, [hashtable]$Body, [string[]]$Expected)
  $f = New-JsonFileFromObj $Body
  $resp = Invoke-ApiSimple "POST" "$baseUrl/api/v1/quality/inspections" @{ "x-company-id"=$CompanyId; "x-role"=$Role } $f
  Assert-Status $resp.Status $Expected "T11 create inspection" $resp.RespPath
  return $resp
}

function T11_ListInspections {
  param([string]$CompanyId)
  $resp = Invoke-ApiSimple "GET" "$baseUrl/api/v1/quality/inspections?limit=20" @{ "x-company-id"=$CompanyId; "x-role"="VIEWER" } $null
  Assert-Status $resp.Status @("200") "T11 list inspections" $resp.RespPath
  return (Get-Content $resp.RespPath -Raw | ConvertFrom-Json).data
}

function T11_AddDefectLine {
  param([string]$CompanyId, [string]$Role, [int]$InspectionId, [int]$DefectTypeId, [double]$Qty, [string[]]$Expected)
  $f = New-JsonFileFromObj @{ defectTypeId=$DefectTypeId; qty=$Qty; note="smoke" }
  $resp = Invoke-ApiSimple "POST" "$baseUrl/api/v1/quality/inspections/$InspectionId/defects" @{ "x-company-id"=$CompanyId; "x-role"=$Role } $f
  Assert-Status $resp.Status $Expected "T11 add defect line" $resp.RespPath
  return $resp
}

Write-Host "[STEP] Ticket-11 준비: COMPANY-A/B 공정/설비/불량유형 확보" -ForegroundColor Cyan
$qaA = T11_EnsureInspectionPrereqs -CompanyId $companyA
$qaB = T11_EnsureInspectionPrereqs -CompanyId $companyB

Write-Host "[STEP] T11 검사 등록 201/409" -ForegroundColor Cyan
$inspNo = "QI-SMOKE-001"
T11_CreateInspection -CompanyId $companyA -Role "OPERATOR" -Expected @("201","409") -Body @{
  inspectionNo = $inspNo
  inspectionType = "FINAL"
  status = "PASS"
  processId = $qaA.processId
  equipmentId = $qaA.equipmentId
  inspectedAt = (Get-Date).ToString("o")
  inspectorName = "smoke"
  note = "smoke"
} | Out-Null

Write-Host "[STEP] T11 VIEWER 검사 등록 차단 403" -ForegroundColor Cyan
T11_CreateInspection -CompanyId $companyA -Role "VIEWER" -Expected @("403") -Body @{
  inspectionNo = "QI-SMOKE-VIEW"
  inspectionType = "FINAL"
  status = "PASS"
  processId = $qaA.processId
} | Out-Null

Write-Host "[STEP] T11 타사 processId 사용 400" -ForegroundColor Cyan
T11_CreateInspection -CompanyId $companyA -Role "OPERATOR" -Expected @("400") -Body @{
  inspectionNo = "QI-SMOKE-BADREF"
  inspectionType = "FINAL"
  status = "PASS"
  processId = $qaB.processId
} | Out-Null

Write-Host "[STEP] T11 검사 불량 라인 등록 201/409 + 조회 200" -ForegroundColor Cyan
$insps = T11_ListInspections -CompanyId $companyA
$insp = ($insps | Where-Object { $_.inspectionNo -eq $inspNo } | Select-Object -First 1)
if (-not $insp) { Write-Host "[FAIL] T11 inspection not found" -ForegroundColor Red; exit 1 }

T11_AddDefectLine -CompanyId $companyA -Role "OPERATOR" -InspectionId $insp.id -DefectTypeId $qaA.defectTypeId -Qty 1 -Expected @("201","409") | Out-Null
$linesResp = Invoke-ApiSimple "GET" "$baseUrl/api/v1/quality/inspections/$($insp.id)/defects" @{ "x-company-id"=$companyA; "x-role"="VIEWER" } $null
Assert-Status $linesResp.Status @("200") "T11 defects list" $linesResp.RespPath

Write-Host "[PASS] Ticket-11 Quality Inspections 스모크 완료" -ForegroundColor Green

# -----------------------------
# Ticket-12 Smoke: Quality Check Items / Results
# -----------------------------
Write-Host "`n[SMOKE] Ticket-12 Quality Check Items 시작" -ForegroundColor Cyan

if (-not $qaA) { $qaA = T11_EnsureInspectionPrereqs -CompanyId $companyA }
if (-not $qaB) { $qaB = T11_EnsureInspectionPrereqs -CompanyId $companyB }

Write-Host "[STEP] T12 검사 항목 등록 201/409" -ForegroundColor Cyan
$checkFile = New-JsonFileFromObj @{
  name="중량"
  code="CHK-WEIGHT"
  dataType="NUMBER"
  unit="g"
  lowerLimit=95
  upperLimit=105
  isRequired=1
}
$checkResp = Invoke-ApiSimple "POST" "$baseUrl/api/v1/quality/check-items" @{ "x-company-id"=$companyA; "x-role"="OPERATOR" } $checkFile
Assert-Status $checkResp.Status @("201","409") "T12 check-item create" $checkResp.RespPath

Write-Host "[STEP] T12 VIEWER 검사 항목 등록 차단 403" -ForegroundColor Cyan
$checkFile2 = New-JsonFileFromObj @{
  name="염도"
  code=("CHK-SALT-" + (Get-Random))
  dataType="NUMBER"
  unit="pct"
  lowerLimit=2
  upperLimit=4
  isRequired=1
}
$checkResp2 = Invoke-ApiSimple "POST" "$baseUrl/api/v1/quality/check-items" @{ "x-company-id"=$companyA; "x-role"="VIEWER" } $checkFile2
Assert-Status $checkResp2.Status @("403") "T12 check-item viewer" $checkResp2.RespPath

Write-Host "[STEP] T12 타사 검사 항목 등록(준비용)" -ForegroundColor Cyan
$checkFileB = New-JsonFileFromObj @{
  name="타사용 중량"
  code="CHK-WEIGHT-B"
  dataType="NUMBER"
  unit="g"
  lowerLimit=95
  upperLimit=105
  isRequired=1
}
$checkRespB = Invoke-ApiSimple "POST" "$baseUrl/api/v1/quality/check-items" @{ "x-company-id"=$companyB; "x-role"="OPERATOR" } $checkFileB
Assert-Status $checkRespB.Status @("201","409") "T12 check-item companyB" $checkRespB.RespPath

Write-Host "[STEP] T12 검사 생성(있으면 재사용)" -ForegroundColor Cyan
$inspNo12 = "QI-SMOKE-12-001"
T11_CreateInspection -CompanyId $companyA -Role "OPERATOR" -Expected @("201","409") -Body @{
  inspectionNo = $inspNo12
  inspectionType = "FINAL"
  status = "PASS"
  processId = $qaA.processId
  equipmentId = $qaA.equipmentId
  inspectedAt = (Get-Date).ToString("o")
} | Out-Null

$insps12 = T11_ListInspections -CompanyId $companyA
$insp12 = ($insps12 | Where-Object { $_.inspectionNo -eq $inspNo12 } | Select-Object -First 1)
if (-not $insp12) { Write-Host "[FAIL] T12 inspection not found" -ForegroundColor Red; exit 1 }

Write-Host "[STEP] T12 검사 결과 등록 201/409 (범위 초과)" -ForegroundColor Cyan
$resFile12 = New-JsonFileFromObj @{
  checkItemCode="CHK-WEIGHT"
  measuredValue=200
  note="범위 초과 스모크"
}
$resResp12 = Invoke-ApiSimple "POST" "$baseUrl/api/v1/quality/inspections/$($insp12.id)/results" @{ "x-company-id"=$companyA; "x-role"="OPERATOR" } $resFile12
Assert-Status $resResp12.Status @("201","409") "T12 result create" $resResp12.RespPath

Write-Host "[STEP] T12 타사 검사 항목 결과 등록 400" -ForegroundColor Cyan
$resFile12B = New-JsonFileFromObj @{
  checkItemCode="CHK-WEIGHT-B"
  measuredValue=100
}
$resResp12B = Invoke-ApiSimple "POST" "$baseUrl/api/v1/quality/inspections/$($insp12.id)/results" @{ "x-company-id"=$companyA; "x-role"="OPERATOR" } $resFile12B
Assert-Status $resResp12B.Status @("400") "T12 result cross-tenant" $resResp12B.RespPath

Write-Host "[PASS] Ticket-12 Quality Check Items 스모크 완료" -ForegroundColor Green

# ---------------------------
# Ticket-13 Smoke: LOT Trace
# ---------------------------
Write-Host "`n[SMOKE] Ticket-13 LOT Trace 시작" -ForegroundColor Cyan

function Smoke13_Print([string]$msg) { Write-Host $msg }

function Smoke13_AssertOneOf([int]$actual, [int[]]$expected, [string]$label) {
  if ($expected -contains $actual) {
    Smoke13_Print "[PASS] $label ($actual)"
  } else {
    throw "[FAIL] $label (expected: $($expected -join ', '), actual: $actual)"
  }
}

function Smoke13_TryJson([string]$raw) {
  if (-not $raw) { return $null }
  try { return ($raw | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}

function Smoke13_GetData($jsonObj) {
  if ($null -eq $jsonObj) { return $null }
  if ($jsonObj.PSObject.Properties.Name -contains "data") { return $jsonObj.data }
  return $jsonObj
}

function Smoke13_Curl([string]$method, [string]$url, [hashtable]$headers, [object]$bodyObj) {
  $out = Join-Path $env:TEMP ("smoke13_" + [guid]::NewGuid().ToString() + ".out.json")
  $dataFile = $null
  $args = @("-s", "-o", $out, "-w", "%{http_code}", "-X", $method)

  foreach ($k in $headers.Keys) {
    $args += @("-H", "${k}: $($headers[$k])")
  }

  if ($null -ne $bodyObj) {
    $dataFile = Join-Path $env:TEMP ("smoke13_" + [guid]::NewGuid().ToString() + ".body.json")
    $json = ($bodyObj | ConvertTo-Json -Depth 50 -Compress)
    Set-Content -LiteralPath $dataFile -Value $json -Encoding utf8
    $args += @("--data-binary", "@$dataFile")
  }

  $statusRaw = & curl.exe @args $url
  $status = 0
  try { $status = [int]$statusRaw } catch { $status = 0 }

  $body = ""
  if (Test-Path $out) { $body = Get-Content $out -Raw -ErrorAction SilentlyContinue }

  if ($dataFile -and (Test-Path $dataFile)) { Remove-Item $dataFile -Force -ErrorAction SilentlyContinue }
  if (Test-Path $out) { Remove-Item $out -Force -ErrorAction SilentlyContinue }

  return @{ Status = $status; Body = $body }
}

function Smoke13_EnsureItemCategory([string]$baseUrl, [string]$companyId, [string]$role, [string]$code, [string]$name) {
  $h = @{ "Content-Type"="application/json"; "x-company-id"=$companyId; "x-role"=$role }
  $r = Smoke13_Curl "POST" "$baseUrl/api/v1/item-categories" $h @{ code=$code; name=$name }
  Smoke13_AssertOneOf $r.Status @(201,409) "Ticket-13 pre: item-category upsert"

  $q = Smoke13_Curl "GET" "$baseUrl/api/v1/item-categories" @{ "x-company-id"=$companyId; "x-role"="VIEWER" } $null
  Smoke13_AssertOneOf $q.Status @(200) "Ticket-13 pre: item-category list"

  $j = Smoke13_TryJson $q.Body
  $data = Smoke13_GetData $j
  $row = $data | Where-Object { $_.code -eq $code } | Select-Object -First 1
  if (-not $row) { throw "[FAIL] Ticket-13 pre: cannot find category by code=$code" }
  return $row.id
}

function Smoke13_EnsureItem([string]$baseUrl, [string]$companyId, [string]$role, [int]$categoryId, [string]$code, [string]$name) {
  $h = @{ "Content-Type"="application/json"; "x-company-id"=$companyId; "x-role"=$role }
  $r = Smoke13_Curl "POST" "$baseUrl/api/v1/items" $h @{ categoryId=$categoryId; code=$code; name=$name }
  Smoke13_AssertOneOf $r.Status @(201,409) "Ticket-13 pre: item upsert"

  $q = Smoke13_Curl "GET" "$baseUrl/api/v1/items" @{ "x-company-id"=$companyId; "x-role"="VIEWER" } $null
  Smoke13_AssertOneOf $q.Status @(200) "Ticket-13 pre: item list"

  $j = Smoke13_TryJson $q.Body
  $data = Smoke13_GetData $j
  $row = $data | Where-Object { $_.code -eq $code } | Select-Object -First 1
  if (-not $row) { throw "[FAIL] Ticket-13 pre: cannot find item by code=$code" }
  return $row.id
}

function Smoke13_CreateLot([string]$baseUrl, [string]$companyId, [string]$role, [object]$payload) {
  $h = @{ "Content-Type"="application/json"; "x-company-id"=$companyId; "x-role"=$role }
  return Smoke13_Curl "POST" "$baseUrl/api/v1/lots" $h $payload
}

function Smoke13_GetTrace([string]$baseUrl, [string]$companyId, [string]$lotNo) {
  $h = @{ "x-company-id"=$companyId; "x-role"="VIEWER" }
  return Smoke13_Curl "GET" "$baseUrl/api/v1/lots/$lotNo/trace?direction=down&depth=3" $h $null
}

$Smoke13_BaseUrl = $env:SMOKE_BASE_URL
if (-not $Smoke13_BaseUrl) { $Smoke13_BaseUrl = "http://localhost:4000" }

$catA = Smoke13_EnsureItemCategory $Smoke13_BaseUrl "COMPANY-A" "OPERATOR" "CAT-LOT" "LOT용 카테고리"
$itemA = Smoke13_EnsureItem $Smoke13_BaseUrl "COMPANY-A" "OPERATOR" $catA "ITEM-LOT-A" "LOT 테스트 품목 A"

$catB = Smoke13_EnsureItemCategory $Smoke13_BaseUrl "COMPANY-B" "OPERATOR" "CAT-LOT" "LOT용 카테고리"
$itemB = Smoke13_EnsureItem $Smoke13_BaseUrl "COMPANY-B" "OPERATOR" $catB "ITEM-LOT-B" "LOT 테스트 품목 B"

# 1) LOT 생성 201/409
$lotNoA = "LOT-A-" + (Get-Date -Format "yyyyMMddHHmmss")
$r1 = Smoke13_CreateLot $Smoke13_BaseUrl "COMPANY-A" "OPERATOR" @{ lotNo=$lotNoA; itemId=$itemA; qty=10; unit="EA"; status="CREATED" }
Smoke13_AssertOneOf $r1.Status @(201,409) "Ticket-13A: LOT 생성(201/409)"

# 2) VIEWER 생성 차단 403
$lotNoViewer = "LOT-V-" + (Get-Date -Format "yyyyMMddHHmmss")
$r2 = Smoke13_CreateLot $Smoke13_BaseUrl "COMPANY-A" "VIEWER" @{ lotNo=$lotNoViewer; itemId=$itemA; qty=1; unit="EA"; status="CREATED" }
Smoke13_AssertOneOf $r2.Status @(403) "Ticket-13A: VIEWER 생성 차단(403)"

# 3) 잘못된 itemId 400
$lotNoBadItem = "LOT-BI-" + (Get-Date -Format "yyyyMMddHHmmss")
$r3 = Smoke13_CreateLot $Smoke13_BaseUrl "COMPANY-A" "OPERATOR" @{ lotNo=$lotNoBadItem; itemId=999999; qty=1; unit="EA"; status="CREATED" }
Smoke13_AssertOneOf $r3.Status @(400) "Ticket-13A: itemId 없음/타사 400"

# 4) 자식 LOT 생성 201/409
$childLotNo = "LOT-CH-" + (Get-Date -Format "yyyyMMddHHmmss")
$r4 = Smoke13_CreateLot $Smoke13_BaseUrl "COMPANY-A" "OPERATOR" @{ lotNo=$childLotNo; itemId=$itemA; parentLotNo=$lotNoA; qty=5; unit="EA"; status="CREATED" }
Smoke13_AssertOneOf $r4.Status @(201,409) "Ticket-13B: 자식 LOT 생성(201/409)"

# 5) 타사 parentLotNo 차단 400
$parentLotB = "LOT-B-" + (Get-Date -Format "yyyyMMddHHmmss")
$upB = Smoke13_CreateLot $Smoke13_BaseUrl "COMPANY-B" "OPERATOR" @{ lotNo=$parentLotB; itemId=$itemB; qty=1; unit="EA"; status="CREATED" }
Smoke13_AssertOneOf $upB.Status @(201,409) "Ticket-13 pre: COMPANY-B LOT 생성"
$badChild = "LOT-XTEN-" + (Get-Date -Format "yyyyMMddHHmmss")
$r5 = Smoke13_CreateLot $Smoke13_BaseUrl "COMPANY-A" "OPERATOR" @{ lotNo=$badChild; itemId=$itemA; parentLotNo=$parentLotB; qty=1; unit="EA"; status="CREATED" }
Smoke13_AssertOneOf $r5.Status @(400) "Ticket-13B: 타사 parentLotNo 차단 400"

# 6) Trace 200
$t = Smoke13_GetTrace $Smoke13_BaseUrl "COMPANY-A" $lotNoA
Smoke13_AssertOneOf $t.Status @(200) "Ticket-13B: trace 조회(200)"

Smoke13_Print "[PASS] Ticket-13 LOT Trace 스모크 완료"

# ---------------------------
# Ticket-13.1 Smoke: Work Order - LOT Link
# ---------------------------
Write-Host "`n[SMOKE] Ticket-13.1 WorkOrder-LOT Link 시작" -ForegroundColor Cyan

Write-Host "[STEP] T13.1 작업지시/LOT 준비 (COMPANY-A)" -ForegroundColor Cyan
$itemLinkA = Ensure-Item -CompanyId $companyA -Code "SMOKE-ITEM-LINK-A"
$procLinkA = Ensure-Process -CompanyId $companyA -ProcCode "SMOKE-PROC-LINK-A"
$eqLinkA = Ensure-Equipment -CompanyId $companyA -EqCode "SMOKE-EQ-LINK-A" -ProcessId $procLinkA

$woNoLink = "WO-LINK-" + (Get-Date -Format "yyyyMMddHHmmss")
$woFileLink = New-JsonFileFromObj @{ woNo=$woNoLink; itemId=$itemLinkA; processId=$procLinkA; equipmentId=$eqLinkA; planQty=1; status="PLANNED" }
$woRespLink = Invoke-ApiSimple "POST" "$baseUrl/api/v1/work-orders" @{ "x-company-id"=$companyA; "x-role"="OPERATOR" } $woFileLink
Assert-Status $woRespLink.Status @("201","409") "T13.1 work-order create" $woRespLink.RespPath

$woListLink = Invoke-ApiSimple "GET" "$baseUrl/api/v1/work-orders?limit=20" @{ "x-company-id"=$companyA; "x-role"="VIEWER" } $null
Assert-Status $woListLink.Status @("200") "T13.1 work-order list" $woListLink.RespPath
$woLink = (Get-Content $woListLink.RespPath -Raw | ConvertFrom-Json).data | Where-Object { $_.woNo -eq $woNoLink } | Select-Object -First 1
if (-not $woLink) { Write-Host "[FAIL] T13.1 work-order not found" -ForegroundColor Red; exit 1 }

$lotNoLink = "LOT-LINK-" + (Get-Date -Format "yyyyMMddHHmmss")
$lotFileLink = New-JsonFileFromObj @{ lotNo=$lotNoLink; itemId=$itemLinkA; qty=1; unit="EA"; status="CREATED" }
$lotRespLink = Invoke-ApiSimple "POST" "$baseUrl/api/v1/lots" @{ "x-company-id"=$companyA; "x-role"="OPERATOR" } $lotFileLink
Assert-Status $lotRespLink.Status @("201","409") "T13.1 lot create" $lotRespLink.RespPath

$lotListLink = Invoke-ApiSimple "GET" "$baseUrl/api/v1/lots?lotNo=$lotNoLink" @{ "x-company-id"=$companyA; "x-role"="VIEWER" } $null
Assert-Status $lotListLink.Status @("200") "T13.1 lot list" $lotListLink.RespPath
$lotLink = (Get-Content $lotListLink.RespPath -Raw | ConvertFrom-Json).data | Select-Object -First 1
if (-not $lotLink) { Write-Host "[FAIL] T13.1 lot not found" -ForegroundColor Red; exit 1 }

Write-Host "[STEP] T13.1 링크 생성 201/409" -ForegroundColor Cyan
$linkResp = Invoke-ApiSimple "POST" "$baseUrl/api/v1/work-orders/$($woLink.id)/lots/$($lotLink.id)/link" @{ "x-company-id"=$companyA; "x-role"="OPERATOR" } $null
Assert-Status $linkResp.Status @("201","409") "T13.1 link create" $linkResp.RespPath

Write-Host "[STEP] T13.1 VIEWER 차단 403" -ForegroundColor Cyan
$linkRespViewer = Invoke-ApiSimple "POST" "$baseUrl/api/v1/work-orders/$($woLink.id)/lots/$($lotLink.id)/link" @{ "x-company-id"=$companyA; "x-role"="VIEWER" } $null
Assert-Status $linkRespViewer.Status @("403") "T13.1 link viewer" $linkRespViewer.RespPath

Write-Host "[STEP] T13.1 타사 LOT 링크 400" -ForegroundColor Cyan
$itemLinkB = Ensure-Item -CompanyId $companyB -Code "SMOKE-ITEM-LINK-B"
$lotNoLinkB = "LOT-LINK-B-" + (Get-Date -Format "yyyyMMddHHmmss")
$lotFileLinkB = New-JsonFileFromObj @{ lotNo=$lotNoLinkB; itemId=$itemLinkB; qty=1; unit="EA"; status="CREATED" }
$lotRespLinkB = Invoke-ApiSimple "POST" "$baseUrl/api/v1/lots" @{ "x-company-id"=$companyB; "x-role"="OPERATOR" } $lotFileLinkB
Assert-Status $lotRespLinkB.Status @("201","409") "T13.1 lot create B" $lotRespLinkB.RespPath

$lotListLinkB = Invoke-ApiSimple "GET" "$baseUrl/api/v1/lots?lotNo=$lotNoLinkB" @{ "x-company-id"=$companyB; "x-role"="VIEWER" } $null
Assert-Status $lotListLinkB.Status @("200") "T13.1 lot list B" $lotListLinkB.RespPath
$lotLinkB = (Get-Content $lotListLinkB.RespPath -Raw | ConvertFrom-Json).data | Select-Object -First 1
if (-not $lotLinkB) { Write-Host "[FAIL] T13.1 lot B not found" -ForegroundColor Red; exit 1 }

$linkRespBad = Invoke-ApiSimple "POST" "$baseUrl/api/v1/work-orders/$($woLink.id)/lots/$($lotLinkB.id)/link" @{ "x-company-id"=$companyA; "x-role"="OPERATOR" } $null
Assert-Status $linkRespBad.Status @("400") "T13.1 link cross-tenant" $linkRespBad.RespPath

Write-Host "[PASS] Ticket-13.1 WorkOrder-LOT Link 스모크 완료" -ForegroundColor Green

# ---------------------------
# Ticket-14 Smoke: Reports
# ---------------------------
Write-Host "`n[SMOKE] Ticket-14 Reports 시작" -ForegroundColor Cyan

$reportTo = (Get-Date).ToString("yyyy-MM-dd")
$reportFrom = (Get-Date).AddDays(-7).ToString("yyyy-MM-dd")

$rep1 = Invoke-ApiSimple "GET" "$baseUrl/api/v1/reports/summary?from=$reportFrom&to=$reportTo" @{ "x-company-id"=$companyA; "x-role"="VIEWER" } $null
Assert-Status $rep1.Status @("200") "T14 summary" $rep1.RespPath

$rep2 = Invoke-ApiSimple "GET" "$baseUrl/api/v1/reports/daily?from=$reportFrom&to=$reportTo" @{ "x-company-id"=$companyA; "x-role"="VIEWER" } $null
Assert-Status $rep2.Status @("200") "T14 daily" $rep2.RespPath

$rep3 = Invoke-ApiSimple "GET" "$baseUrl/api/v1/reports/top-defects?from=$reportFrom&to=$reportTo&limit=10" @{ "x-company-id"=$companyA; "x-role"="VIEWER" } $null
Assert-Status $rep3.Status @("200") "T14 top-defects" $rep3.RespPath

$rep4 = Invoke-ApiSimple "GET" "$baseUrl/api/v1/reports/summary?from=2025-99-99&to=$reportTo" @{ "x-company-id"=$companyA; "x-role"="VIEWER" } $null
Assert-Status $rep4.Status @("400") "T14 invalid date" $rep4.RespPath

$rep5 = Invoke-ApiSimple "GET" "$baseUrl/api/v1/reports/top-defects?limit=999" @{ "x-company-id"=$companyA; "x-role"="VIEWER" } $null
Assert-Status $rep5.Status @("400") "T14 invalid limit" $rep5.RespPath

Write-Host "[PASS] Ticket-14 Reports 스모크 완료" -ForegroundColor Green

# ---------------------------
# Ticket-14.1b Smoke: Report Cache Purge
# ---------------------------
Write-Host "`n[SMOKE] Ticket-14.1b Report Cache Purge 시작" -ForegroundColor Cyan

$env:REPORT_KPI_CACHE_MODE = "PREFER"
$env:REPORT_KPI_CACHE_TTL_SECONDS = "600"
$env:REPORT_KPI_CACHE_PURGE_ENABLED = "1"

for ($i=0; $i -lt 30; $i++) {
  $fromPurge = (Get-Date).AddDays(-7-$i).ToString("yyyy-MM-dd")
  $toPurge   = (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")
  $url = "$baseUrl/api/v1/reports/summary?from=$fromPurge&to=$toPurge"
  $null = Invoke-ApiSimple "GET" $url @{ "x-company-id"=$companyA; "x-role"="VIEWER" } $null
}

$env:REPORT_KPI_CACHE_MAX_ROWS_PER_COMPANY = "10"

$before = node -e "const db=require('./src/db'); db.init(); console.log(db.countReportKpiCacheRows({companyId:'COMPANY-A'}));"
Write-Host "[INFO][T14.1b] before rows: $before"

node -e "const db=require('./src/db'); db.init(); db.purgeReportKpiCacheNow({ maxRowsPerCompany: 10 }); console.log('purge-ok');" | Out-Null

$after = node -e "const db=require('./src/db'); db.init(); console.log(db.countReportKpiCacheRows({companyId:'COMPANY-A'}));"
Write-Host "[INFO][T14.1b] after rows: $after"

if ([int]$after -le 10) {
  Write-Host "[PASS] Ticket-14.1b purge maxRowsPerCompany 적용 확인" -ForegroundColor Green
  Write-Host "[PASS] Ticket-14.1b Report Cache Purge 스모크 완료" -ForegroundColor Green
} else {
  Write-Host "[FAIL] Ticket-14.1b purge 실패: rows(after)=$after > 10" -ForegroundColor Red
  exit 1
}

# ---------------------------
# Optional ERD Gate
# ---------------------------
Invoke-ErdGate -DbPath "data/mes.db" -OutDir "docs/erd"
