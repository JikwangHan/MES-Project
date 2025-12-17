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
