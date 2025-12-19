# MES Project

MES(Project) 저장소입니다. 이 문서는 **처음 GitHub를 쓰는 초보자**도 따라 할 수 있도록 단계별로 설명합니다. 아래 안내만 그대로 따라 하면 프로젝트를 내려받고, 간단한 예제 서버를 실행해 볼 수 있습니다.

## 1) 준비물
- Git: https://git-scm.com 에서 설치 (기본 설정 그대로 Next를 눌러도 됩니다)
- 코드 편집기: Visual Studio Code 추천
- Node.js 18 이상(예제 서버 실행용): https://nodejs.org 에서 LTS 버전 설치

## 2) 프로젝트 내려받기
PowerShell(또는 명령 프롬프트)을 열고 아래 명령을 입력합니다.
```bash
git clone https://github.com/JikwangHan/MES-Project.git
cd MES-Project
```
정상적으로 내려받으면 `MES-Project` 폴더 안에 `README.md`와 `src` 폴더가 보입니다.

## 3) 폴더 구조 미리보기
```
MES-Project/
├─ README.md                  # 이 문서
├─ .gitignore                 # Git에 올리지 않을 파일 목록
├─ package.json               # 실행/의존성 정의
├─ package-lock.json
├─ data/                      # SQLite DB 파일 저장 위치(자동 생성)
├─ src/
│  ├─ server.js               # 메인 API 서버 엔트리
│  ├─ db.js                   # SQLite 연결/스키마 초기화
│  ├─ routes/
│  │  └─ itemCategories.js    # Ticket-01: 품목유형 API
│  ├─ middleware/
│  │  ├─ tenant.js            # x-company-id 헤더 확인
│  │  └─ auth.js              # x-role 헤더, VIEWER 제한
│  ├─ utils/response.js       # 표준 응답 포맷
│  └─ example-server.js       # 기존 단순 예제 서버(검증용)
└─ node_modules/ (자동 생성)
```

## 4) 바로 실행해보는 예제 (Node.js 내장 http 사용)
아래 단계는 “서버가 제대로 동작하는지” 확인하는 가장 단순한 예시입니다.

1. 프로젝트 폴더로 이동: `cd MES-Project`
2. 서버 실행: `node src/example-server.js`
3. PowerShell 화면에 `Server running at http://localhost:4000` 이 보이면 성공입니다.
4. 웹 브라우저 주소창에 `http://localhost:4000` 입력 → “MES Project 서버가 정상 동작 중입니다.” 문구가 보이면 OK.

### 예제 서버 코드 살펴보기
`src/example-server.js` 파일에 들어 있는 코드입니다. 그대로 실행만 해도 되고, 메시지를 바꾸면서 테스트해도 됩니다.
```javascript
const http = require('http');

const PORT = 4000;

const server = http.createServer((req, res) => {
  // 간단한 텍스트 응답
  res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end('MES Project 서버가 정상 동작 중입니다.');
});

server.listen(PORT, () => {
  console.log(`Server running at http://localhost:${PORT}`);
});
```

## 5) 정밀 개발 2차 – Ticket-01 API 바로 실행하기 (초보자용)
아래 순서대로 따라 하면 “품목유형 등록/조회 API”를 바로 띄워볼 수 있습니다.

1. 프로젝트 폴더로 이동  
   ```bash
   cd MES-Project
   ```
2. 의존성 설치(처음 한 번만)  
   ```bash
   npm install
   ```
3. API 서버 실행  
   ```bash
   npm start
   ```
   - PowerShell에 `MES API server running at http://localhost:4000` 메시지가 보이면 성공입니다.

### 헤더 규칙 (멀티테넌트 + RBAC)
- `x-company-id`: **회사 식별자** (필수) – 테넌트 분리용
- `x-role`: **사용자 역할** – `OPERATOR`, `MANAGER` 등. `VIEWER`는 등록 불가(403).

### 5-1) 품목유형 등록 (POST /api/v1/item-categories)
예제: 회사 A(OPERATOR)가 “완제품” 카테고리를 등록
```bash
curl -X POST http://localhost:4000/api/v1/item-categories ^
  -H "Content-Type: application/json" ^
  -H "x-company-id: COMPANY-A" ^
  -H "x-role: OPERATOR" ^
  -d "{ \"name\": \"완제품\", \"code\": \"FINISHED\" }"
```
- 성공 시 201 Created와 함께 등록된 데이터가 JSON으로 돌아옵니다.
- 같은 회사에서 `code`가 중복되면 409 응답을 받습니다.

### 5-2) 품목유형 조회 (GET /api/v1/item-categories)
```bash
curl -X GET http://localhost:4000/api/v1/item-categories ^
  -H "x-company-id: COMPANY-A" ^
  -H "x-role: VIEWER"
```
- 회사별(`x-company-id`)로만 필터링되어 반환됩니다.
- VIEWER도 조회는 가능하지만 등록은 불가합니다.

### 5-3) 감사 로그(audit_logs) 확인 (옵션)
`data/mes.db`는 SQLite 파일입니다. `DB Browser for SQLite` 같은 무료 툴로 열어서 `audit_logs` 테이블을 보면 누가(역할), 어떤 엔티티를, 언제 만들었는지 확인 가능합니다.

## 6) Ticket-02 품목(Item) 등록/조회 API 실행하기
Ticket-01과 같은 패턴으로 바로 테스트할 수 있습니다.

1. 서버 실행  
   ```bash
   npm start
   ```
2. 등록 성공 (OPERATOR, 회사 A, 카테고리 id=1 사용 예시)  
   ```bash
   curl.exe -X POST "http://localhost:4000/api/v1/items" ^
     -H "Content-Type: application/json" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: OPERATOR" ^
     -d "{\"categoryId\":1,\"name\":\"라면\",\"code\":\"ITEM-001\"}"
   ```
   - 같은 회사(`x-company-id`)에서 `code`가 중복되면 409가 반환됩니다.
3. 조회 (VIEWER도 가능)  
   ```bash
   curl.exe -X GET "http://localhost:4000/api/v1/items" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: VIEWER"
   ```
4. 실패 케이스 예시  
   - `x-role: VIEWER`로 POST → 403  
   - 다른 회사의 categoryId 사용 → 403  
   - 존재하지 않는 categoryId → 400  
5. 감사 로그 확인  
   - `data/mes.db`의 `audit_logs`에서 성공(`CREATE`)과 실패(`CREATE_FAIL`) 기록을 확인할 수 있습니다.

## 7) Ticket-03 PL/BOM API 실행하기
완제품(itemId)에 자재(childItemId)와 수량/단위를 연결하는 API입니다.

1. BOM 추가 (OPERATOR, 회사 A, 완제품 id=1, 자재 id=2 예시)  
   ```powershell
   curl.exe -X POST "http://localhost:4000/api/v1/items/1/parts" ^
     -H "Content-Type: application/json" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: OPERATOR" ^
     -d "{\"childItemId\":2,\"qty\":1.5,\"unit\":\"EA\"}"
   ```
   - 규칙: `qty`는 0보다 커야 합니다. 부모/자식이 같으면 400, 중복 연결이면 409.
2. BOM 조회 (VIEWER도 가능)  
   ```powershell
   curl.exe -X GET "http://localhost:4000/api/v1/items/1/parts" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: VIEWER"
   ```
3. 삭제 (필요 시, OPERATOR)  
   ```powershell
   curl.exe -X DELETE "http://localhost:4000/api/v1/items/1/parts/파트ID" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: OPERATOR"
   ```
4. 실패 케이스 예시  
   - VIEWER로 추가 → 403  
   - parent/child가 동일 → 400(BOM_SELF_REFERENCE)  
   - 같은 parent+child 중복 → 409(BOM_DUPLICATE)  
   - 다른 회사의 itemId/childItemId 사용 → 400(ITEM_NOT_FOUND로 통일)  
5. 감사 로그 확인  
   - `audit_logs`에서 `entity=item_boms`의 CREATE/DELETE/FAIL 기록을 확인할 수 있습니다.

## 8) Ticket-04 공정(Process) API 실행하기
공정을 상위/하위 구조로 관리합니다. (이번 티켓은 등록/조회만)

1. 공정 등록 (OPERATOR, parent 없이)  
   ```powershell
   curl.exe -X POST "http://localhost:4000/api/v1/processes" ^
     -H "Content-Type: application/json" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: OPERATOR" ^
     -d "{\"name\":\"포장공정\",\"code\":\"PROC-001\",\"parentId\":null,\"sortOrder\":0}"
   ```
   - 같은 회사에서 code가 중복이면 409(PROCESS_CODE_DUPLICATE).
   - parentId가 존재하지 않거나 다른 회사이면 400(PROCESS_PARENT_NOT_FOUND).
2. 공정 조회 (VIEWER도 가능)  
   ```powershell
   curl.exe -X GET "http://localhost:4000/api/v1/processes" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: VIEWER"
   ```
3. 실패 케이스 예시  
   - VIEWER로 등록 → 403  
   - parentId가 없거나 타사 → 400(PROCESS_PARENT_NOT_FOUND)
4. 감사 로그 확인  
   - `audit_logs`에서 `entity=processes` CREATE/FAIL 기록 확인 가능.

## 9) Ticket-05 설비(Equipment) API 실행하기
설비를 등록/조회합니다. 이번 티켓은 삭제 제외.

1. 설비 등록 (OPERATOR, processId 없이)  
   ```powershell
   curl.exe -X POST "http://localhost:4000/api/v1/equipments" ^
     -H "Content-Type: application/json" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: OPERATOR" ^
     -d "{\"name\":\"포장기\",\"code\":\"EQ-001\",\"processId\":null,\"commType\":\"MODBUS_TCP\",\"commConfig\":{\"ip\":\"192.168.0.10\",\"port\":502},\"isActive\":1}"
   ```
   - 같은 회사에서 code 중복 → 409(EQUIPMENT_CODE_DUPLICATE)
   - processId가 없거나 타사/없는 공정 → 400(EQUIPMENT_PROCESS_NOT_FOUND)
2. 설비 조회 (VIEWER도 가능)  
   ```powershell
   curl.exe -X GET "http://localhost:4000/api/v1/equipments" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: VIEWER"
   ```
3. 실패 케이스 예시  
   - VIEWER로 등록 → 403  
   - 타사/없는 processId → 400(EQUIPMENT_PROCESS_NOT_FOUND)
4. 감사 로그 확인  
   - `audit_logs`에서 `entity=equipments` CREATE/FAIL 기록 확인 가능.

## 10) Ticket-06 불량유형(Defect Types) API 실행하기
불량유형을 등록/조회합니다. 이번 티켓은 삭제 제외.

1. 불량유형 등록 (OPERATOR, processId 없이)  
   ```powershell
   curl.exe -X POST "http://localhost:4000/api/v1/defect-types" ^
     -H "Content-Type: application/json" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: OPERATOR" ^
     -d "{\"name\":\"스크래치\",\"code\":\"DEF-001\",\"processId\":null,\"severity\":2,\"isActive\":1}"
   ```
   - 같은 회사에서 code 중복 → 409(DEFECT_CODE_DUPLICATE)
   - processId가 없거나 타사/없는 공정 → 400(DEFECT_PROCESS_NOT_FOUND)
2. 불량유형 조회 (VIEWER도 가능)  
   ```powershell
   curl.exe -X GET "http://localhost:4000/api/v1/defect-types" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: VIEWER"
   ```
3. 실패 케이스 예시  
   - VIEWER로 등록 → 403  
   - 타사/없는 processId → 400(DEFECT_PROCESS_NOT_FOUND)
4. 감사 로그 확인  
   - `audit_logs`에서 `entity=defect_types` CREATE/FAIL 기록 확인 가능.

## 11) Ticket-07 거래처(Partners) API 실행하기
거래처를 등록/조회합니다. 이번 티켓은 삭제 제외.

1. 거래처 등록 (OPERATOR)  
   ```powershell
   curl.exe -X POST "http://localhost:4000/api/v1/partners" ^
     -H "Content-Type: application/json" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: OPERATOR" ^
     -d "{\"name\":\"ABC 상사\",\"code\":\"PART-001\",\"type\":\"CUSTOMER\",\"isActive\":1}"
   ```
   - 같은 회사에서 code 중복 → 409(PARTNER_CODE_DUPLICATE)
   - type이 CUSTOMER/VENDOR/BOTH가 아니면 400(PARTNER_TYPE_INVALID)
2. 거래처 조회 (VIEWER도 가능)  
   ```powershell
   curl.exe -X GET "http://localhost:4000/api/v1/partners" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: VIEWER"
   ```
3. 실패 케이스 예시  
   - VIEWER로 등록 → 403  
   - 잘못된 type → 400(PARTNER_TYPE_INVALID)
4. 감사 로그 확인  
   - `audit_logs`에서 `entity=partners` CREATE/FAIL 기록 확인 가능.

## 12) Ticket-08 Telemetry(최소 수신) API 실행하기
장비/게이트웨이가 이벤트를 업로드하는 최소 API입니다.

1. 이벤트 수신 (equipmentCode 필수)  
   ```powershell
   curl.exe -X POST "http://localhost:4000/api/v1/telemetry/events" ^
     -H "Content-Type: application/json" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: VIEWER" ^  # Ticket-08: VIEWER도 허용(장비 수신 목적)
     -d "{\"equipmentCode\":\"EQ-001\",\"timestamp\":\"2025-12-17T12:00:00+09:00\",\"eventType\":\"STATUS\",\"payload\":{\"state\":\"RUN\",\"speed\":120}}"
   ```
   - equipmentCode 없으면 400(TELEMETRY_EQUIPMENT_CODE_REQUIRED)
   - 해당 회사 설비 코드가 아니면 400(TELEMETRY_EQUIPMENT_NOT_FOUND)
2. 이벤트 조회 (VIEWER 허용)  
   ```powershell
   curl.exe -X GET "http://localhost:4000/api/v1/telemetry/events?limit=20" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: VIEWER"
   ```
3. 실패 케이스 예시  
   - equipmentCode 누락 → 400  
   - 타사/없는 equipmentCode → 400  
   - limit가 숫자 아님/0/200 초과 → 400(TELEMETRY_LIMIT_INVALID)
4. 감사 로그 확인  
   - `audit_logs`에서 `entity=telemetry_events` CREATE/FAIL 기록 확인 가능.

※ Ticket-09(보안 강화) 이후에는 Telemetry POST 시 추가 헤더 필요  
`x-device-key`, `x-ts`(epoch), `x-nonce`, `x-signature`(HMAC-SHA256)  
— 디바이스 키 발급 API(`/api/v1/equipments/:id/device-key`)로 key/secret을 받은 뒤 서명 계산(스모크 참고).

## 13) Ticket-11 품질 검사(Inspection) API 실행하기
품질 검사 헤더와 불량 라인을 기록하는 최소 API입니다.

1. 검사 등록 (OPERATOR)
   ```powershell
   curl.exe -X POST "http://localhost:4000/api/v1/quality/inspections" ^
     -H "Content-Type: application/json" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: OPERATOR" ^
     -d "{\"inspectionNo\":\"QI-2025-0001\",\"inspectionType\":\"FINAL\",\"status\":\"PASS\",\"processId\":1,\"equipmentId\":1}"
   ```
   - 같은 회사에서 inspectionNo 중복 → 409(QUALITY_INSPECTION_NO_DUPLICATE)
   - inspectionType/ status 값이 잘못되면 400
2. 검사 조회 (VIEWER도 가능)
   ```powershell
   curl.exe -X GET "http://localhost:4000/api/v1/quality/inspections?limit=20" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: VIEWER"
   ```
3. VIEWER 등록 차단 (403)
   ```powershell
   curl.exe -X POST "http://localhost:4000/api/v1/quality/inspections" ^
     -H "Content-Type: application/json" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: VIEWER" ^
     -d "{\"inspectionNo\":\"QI-VIEW-0001\",\"inspectionType\":\"FINAL\",\"status\":\"PASS\",\"processId\":1}"
   ```
4. 불량 라인 등록 (OPERATOR)
   ```powershell
   curl.exe -X POST "http://localhost:4000/api/v1/quality/inspections/1/defects" ^
     -H "Content-Type: application/json" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: OPERATOR" ^
     -d "{\"defectTypeId\":1,\"qty\":2,\"note\":\"scratch\"}"
   ```
5. 불량 라인 조회 (VIEWER도 가능)
   ```powershell
   curl.exe -X GET "http://localhost:4000/api/v1/quality/inspections/1/defects" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: VIEWER"
   ```
6. 감사 로그 확인
   - `audit_logs`에서 `entity=quality_inspections`와 `quality_inspection_defects`의 CREATE/FAIL 기록 확인 가능.

## 14) Ticket-12 품질 검사 항목 상세(측정값/판정) API 실행하기
검사 항목 마스터와 검사 결과(측정값/판정) 기록 API입니다.

1. 검사 항목 등록 (OPERATOR)
   ```powershell
   curl.exe -X POST "http://localhost:4000/api/v1/quality/check-items" ^
     -H "Content-Type: application/json" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: OPERATOR" ^
     -d "{\"name\":\"중량\",\"code\":\"CHK-WEIGHT\",\"dataType\":\"NUMBER\",\"unit\":\"g\",\"lowerLimit\":95,\"upperLimit\":105,\"isRequired\":1}"
   ```
   - 같은 회사에서 code 중복 → 409(QUALITY_CHECK_ITEM_CODE_DUPLICATE)
2. 검사 항목 조회 (VIEWER도 가능)
   ```powershell
   curl.exe -X GET "http://localhost:4000/api/v1/quality/check-items" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: VIEWER"
   ```
3. VIEWER 등록 차단 (403)
   ```powershell
   curl.exe -X POST "http://localhost:4000/api/v1/quality/check-items" ^
     -H "Content-Type: application/json" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: VIEWER" ^
     -d "{\"name\":\"염도\",\"code\":\"CHK-SALT\",\"dataType\":\"NUMBER\",\"unit\":\"pct\",\"lowerLimit\":2,\"upperLimit\":4,\"isRequired\":1}"
   ```
4. 검사 결과 등록 (측정값이 규격 밖 → FAIL 판정)
   ```powershell
   curl.exe -X POST "http://localhost:4000/api/v1/quality/inspections/1/results" ^
     -H "Content-Type: application/json" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: OPERATOR" ^
     -d "{\"checkItemCode\":\"CHK-WEIGHT\",\"measuredValue\":200,\"note\":\"범위 초과 테스트\"}"
   ```
5. 검사 결과 조회
   ```powershell
   curl.exe -X GET "http://localhost:4000/api/v1/quality/inspections/1/results?limit=20" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: VIEWER"
   ```
6. 타사 검사 항목으로 결과 등록(400)
   ```powershell
   curl.exe -X POST "http://localhost:4000/api/v1/quality/inspections/1/results" ^
     -H "Content-Type: application/json" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: OPERATOR" ^
     -d "{\"checkItemCode\":\"CHK-WEIGHT-B\",\"measuredValue\":100}"
   ```

## 15) Ticket-13 LOT 추적(Trace) API 실행하기
LOT 마스터 생성과 계보(Trace) 조회 API입니다.

1. LOT 생성 (OPERATOR)
   ```powershell
   curl.exe -X POST "http://localhost:4000/api/v1/lots" ^
     -H "Content-Type: application/json" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: OPERATOR" ^
     -d "{\"lotNo\":\"LOT-A-001\",\"itemId\":1,\"qty\":10,\"unit\":\"EA\",\"status\":\"CREATED\"}"
   ```
   - 같은 회사에서 lotNo 중복 → 409(LOT_NO_DUPLICATE)
   - itemId가 없거나 타사 → 400(LOT_ITEM_NOT_FOUND)
2. 자식 LOT 생성
   ```powershell
   curl.exe -X POST "http://localhost:4000/api/v1/lots" ^
     -H "Content-Type: application/json" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: OPERATOR" ^
     -d "{\"lotNo\":\"LOT-A-001-CH1\",\"itemId\":1,\"parentLotNo\":\"LOT-A-001\",\"qty\":5,\"unit\":\"EA\",\"status\":\"CREATED\"}"
   ```
3. VIEWER 생성 차단 (403)
   ```powershell
   curl.exe -X POST "http://localhost:4000/api/v1/lots" ^
     -H "Content-Type: application/json" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: VIEWER" ^
     -d "{\"lotNo\":\"LOT-V-001\",\"itemId\":1,\"qty\":1,\"unit\":\"EA\",\"status\":\"CREATED\"}"
   ```
4. 잘못된 itemId(400)
   ```powershell
   curl.exe -X POST "http://localhost:4000/api/v1/lots" ^
     -H "Content-Type: application/json" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: OPERATOR" ^
     -d "{\"lotNo\":\"LOT-BADITEM-001\",\"itemId\":999999,\"qty\":1,\"unit\":\"EA\",\"status\":\"CREATED\"}"
   ```
5. Trace 조회 (200)
   ```powershell
   curl.exe -X GET "http://localhost:4000/api/v1/lots/LOT-A-001/trace?direction=down&depth=3" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: VIEWER"
   ```
6. 감사 로그 확인
   - `audit_logs`에서 `entity=lots` CREATE/FAIL 기록 확인 가능.

## 15-1) Ticket-13.1 작업지시-LOT 링크 API 실행하기
작업지시와 LOT을 연결하는 최소 운영형 API입니다.

1. 링크 생성 (OPERATOR)
   ```powershell
   curl.exe -X POST "http://localhost:4000/api/v1/work-orders/1/lots/1/link" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: OPERATOR"
   ```
   - 같은 링크가 이미 있으면 409(WO_LOT_LINK_DUPLICATE)
2. VIEWER 차단 (403)
   ```powershell
   curl.exe -X POST "http://localhost:4000/api/v1/work-orders/1/lots/1/link" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: VIEWER"
   ```
3. 타사 workOrder/lot 사용 (400)
   ```powershell
   curl.exe -X POST "http://localhost:4000/api/v1/work-orders/999/lots/999/link" ^
     -H "x-company-id: COMPANY-A" ^
     -H "x-role: OPERATOR"
   ```

## 16) 자주 쓰는 Git 명령 (초보자용)
 - 변경 사항 확인: `git status`
 - 파일 추가/갱신 상태 확인: `git status -sb` (요약)
 - 새 파일 스테이징: `git add 파일명`
 - 커밋 만들기: `git commit -m "메시지"`
 - GitHub로 올리기: `git push origin main` (처음 푸시하는 경우 브랜치 이름을 확인하세요. 기본은 `main`)

## 16-1) 릴리즈 게이트(원클릭) 및 baseline 태그 자동화
운영 단계에서는 태그 오타/중복을 줄이기 위해 자동 스크립트를 사용하는 것을 권장합니다.

1) 다음 baseline 태그 계산만(출력만)
```powershell
pwsh .\tools\baseline-tag.ps1
```

2) 릴리즈 게이트 원클릭(DryRun)
```powershell
$env:MES_MASTER_KEY="dev-master-key"
pwsh .\tools\release-gate.ps1
```

3) 태그 생성 + 원격 푸시까지
```powershell
$env:MES_MASTER_KEY="dev-master-key"
pwsh .\tools\release-gate.ps1 -ApplyTag -PushTag
```

## 17) 다음 단계 제안
 - 프로젝트 목표와 요구사항을 정리한 문서 추가 (예: `docs/requirements.md`)
 - 백엔드/프론트엔드 선택 후 폴더 구조 잡기 (예: `backend/`, `frontend/`)
 - 테스트 자동화 도입 (예: Jest, Vitest, Pytest 등 스택에 맞춰 선택)

필요한 스택이나 세부 구조를 알려주시면, 거기에 맞춘 설정 파일과 예제 코드를 더 추가해드리겠습니다.

## 18) Ticket-14 리포트/통계 API 실행하기
조회 전용 리포트 API입니다. 데이터가 없어도 200으로 응답합니다.

1. 요약 리포트 (summary)
```powershell
curl.exe -X GET "http://localhost:4000/api/v1/reports/summary?from=2025-01-01&to=2025-01-07" `
  -H "x-company-id: COMPANY-A" `
  -H "x-role: VIEWER"
```

2. 일별 리포트 (daily)
```powershell
curl.exe -X GET "http://localhost:4000/api/v1/reports/daily?from=2025-01-01&to=2025-01-07" `
  -H "x-company-id: COMPANY-A" `
  -H "x-role: VIEWER"
```

3. 불량 상위 리포트 (top-defects)
```powershell
curl.exe -X GET "http://localhost:4000/api/v1/reports/top-defects?from=2025-01-01&to=2025-01-07&limit=5" `
  -H "x-company-id: COMPANY-A" `
  -H "x-role: VIEWER"
```

4. 잘못된 날짜 형식 (400)
```powershell
curl.exe -X GET "http://localhost:4000/api/v1/reports/summary?from=2025-99-99&to=2025-01-01" `
  -H "x-company-id: COMPANY-A" `
  -H "x-role: VIEWER"
```

5. 잘못된 날짜 범위 (400)
```powershell
curl.exe -X GET "http://localhost:4000/api/v1/reports/daily?from=2025-12-31&to=2025-01-01" `
  -H "x-company-id: COMPANY-A" `
  -H "x-role: VIEWER"
```

6. limit 범위 초과 (400)
```powershell
curl.exe -X GET "http://localhost:4000/api/v1/reports/top-defects?limit=999" `
  -H "x-company-id: COMPANY-A" `
  -H "x-role: VIEWER"
```

## 19) Ticket-15 대시보드(Dashboard) API 실행하기
대시보드 위젯용 조회 API입니다. 조회 전용이라 VIEWER도 사용 가능합니다.

1. 대시보드 요약(overview)
```powershell
curl.exe -X GET "http://localhost:4000/api/v1/dashboard/overview?days=7" `
  -H "x-company-id: COMPANY-A" `
  -H "x-role: VIEWER"
```

2. 대시보드 활동(activity)
```powershell
curl.exe -X GET "http://localhost:4000/api/v1/dashboard/activity?days=14" `
  -H "x-company-id: COMPANY-A" `
  -H "x-role: VIEWER"
```

3. 대시보드 알림(alerts)
```powershell
curl.exe -X GET "http://localhost:4000/api/v1/dashboard/alerts?limit=5" `
  -H "x-company-id: COMPANY-A" `
  -H "x-role: VIEWER"
```

4. 잘못된 days (400)
```powershell
curl.exe -X GET "http://localhost:4000/api/v1/dashboard/activity?days=0" `
  -H "x-company-id: COMPANY-A" `
  -H "x-role: VIEWER"
```

5. 잘못된 limit (400)
```powershell
curl.exe -X GET "http://localhost:4000/api/v1/dashboard/alerts?limit=999" `
  -H "x-company-id: COMPANY-A" `
  -H "x-role: VIEWER"
```

6. 멀티테넌트 분리 확인 (COMPANY-B 조회)
```powershell
curl.exe -X GET "http://localhost:4000/api/v1/dashboard/overview?days=7" `
  -H "x-company-id: COMPANY-B" `
  -H "x-role: VIEWER"
```
