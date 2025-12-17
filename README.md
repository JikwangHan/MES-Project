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

## 10) 자주 쓰는 Git 명령 (초보자용)
 - 변경 사항 확인: `git status`
 - 파일 추가/갱신 상태 확인: `git status -sb` (요약)
 - 새 파일 스테이징: `git add 파일명`
 - 커밋 만들기: `git commit -m "메시지"`
 - GitHub로 올리기: `git push origin main` (처음 푸시하는 경우 브랜치 이름을 확인하세요. 기본은 `main`)

## 11) 다음 단계 제안
 - 프로젝트 목표와 요구사항을 정리한 문서 추가 (예: `docs/requirements.md`)
 - 백엔드/프론트엔드 선택 후 폴더 구조 잡기 (예: `backend/`, `frontend/`)
 - 테스트 자동화 도입 (예: Jest, Vitest, Pytest 등 스택에 맞춰 선택)

필요한 스택이나 세부 구조를 알려주시면, 거기에 맞춘 설정 파일과 예제 코드를 더 추가해드리겠습니다.
