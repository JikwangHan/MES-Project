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

function BuildTeleHeadersT08($bodyRaw) {
  $bodyObj = $bodyRaw | ConvertFrom-Json
  $bodyCanonical = $bodyObj | ConvertTo-Json -Compress -Depth 6
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
$rawOk | ForEach-Object {
  if ($env:SMOKE_DEBUG_TELEMETRY -eq "1") {
    Write-Host "[DEBUG][T08] client raw body:" -ForegroundColor Yellow
    Write-Host $_ -ForegroundColor Yellow
  }
}
$headersOk = BuildTeleHeadersT08 $rawOk
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
$rawMissing = Get-Content $telePathMissing -Raw
$headersMissing = BuildTeleHeadersT08 $rawMissing
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
$rawCross = Get-Content $telePathCross -Raw
$headersCross = BuildTeleHeadersT08 $rawCross
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
$teleObj9 = $teleRaw9 | ConvertFrom-Json
$teleCanonical9 = $teleObj9 | ConvertTo-Json -Compress -Depth 6
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
  $bodyCanonical = $bodyObj | ConvertTo-Json -Compress -Depth 6
  $bodyHash = Sha256HexStr $bodyCanonical
  $tsEpoch = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $nonce = ([Guid]::NewGuid().ToString("N"))
  $canonical = "$CompanyId`n$DeviceKeyId`n$tsEpoch`n$nonce`n$bodyHash"
  $signature = HmacSha256HexStr $DeviceSecret $canonical

  $tmp = New-TempJsonFile "t09_1_tel_$tsEpoch" $bodyCanonical
  $resp = Invoke-CurlJsonAuth "POST" "$baseUrl/api/v1/telemetry/events" $CompanyId "VIEWER" $tmp @{
    "x-device-key" = $DeviceKeyId
    "x-ts" = "$tsEpoch"
    "x-nonce" = $nonce
    "x-signature" = $signature
  }
  Assert-Status $resp.Status $Expected "[T09.1] telemetry signed" $resp.RespFile
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
