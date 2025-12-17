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
