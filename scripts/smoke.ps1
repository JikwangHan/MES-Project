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
