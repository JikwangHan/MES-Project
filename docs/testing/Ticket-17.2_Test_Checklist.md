# Ticket-17.2 테스트 체크리스트 (초보자용)

이 문서는 **누구나 같은 순서로 테스트를 수행**하고, **PASS/FAIL 근거를 남길 수 있도록** 만든 템플릿입니다.
각 항목은 실제 테스트 전에 **환경값과 입력값을 확인**한 뒤 진행하세요.

## 공통 사전 조건
- MES 서버 실행: `node src/server.js`
- 기본 헤더:
  - `x-company-id: COMPANY-A`
  - `x-role: OPERATOR` (읽기만이면 VIEWER)
- 환경변수(필요 시):
  - `MES_BASE_URL` (기본값: `http://localhost:4000`)
  - `MES_SIGNING_ENABLED` (서명 테스트 시 `1`)
  - `MES_DEVICE_KEY`, `MES_DEVICE_SECRET` (서명 테스트 시 필요, 값 출력 금지)

---

## MES API 테스트

### 템플릿(각 항목 복사해서 사용)
```
- 테스트 ID:
  컴포넌트: MES
  테스트 URL:
  시나리오(무엇을 확인하나?):
  권한(ROLE):
  입력값(Body/Query):
  기대결과:
  PASS/FAIL:
  근거 로그 라인(1~3줄):
  비고:
```

### 예시 (건강 상태 확인)
```
- 테스트 ID: MES-HEALTH-01
  컴포넌트: MES
  테스트 URL: http://localhost:4000/health
  시나리오: 서버가 정상 응답하는지 확인
  권한(ROLE): VIEWER
  입력값(Body/Query): 없음
  기대결과: 200 OK, {"success":true}
  PASS/FAIL: PASS
  근거 로그 라인(1~3줄): HTTP/1.1 200 OK
  비고: 없음
```

---

## Gateway 테스트

### 템플릿(각 항목 복사해서 사용)
```
- 테스트 ID:
  컴포넌트: Gateway
  테스트 URL(또는 실행 명령):
  시나리오(무엇을 확인하나?):
  권한(ROLE):
  입력값(Body/Query/Env):
  기대결과:
  PASS/FAIL:
  근거 로그 라인(1~3줄):
  비고:
```

### 예시 (Gateway smoke - 서명 ON)
```
- 테스트 ID: GW-SMOKE-01
  컴포넌트: Gateway
  테스트 URL(또는 실행 명령): pwsh -NoProfile -ExecutionPolicy Bypass -File .\edge-gateway\scripts\smoke-gateway.ps1
  시나리오: 게이트웨이 uplink 201 확인
  권한(ROLE): VIEWER (서명 테스트 시 내부적으로 device-key 사용)
  입력값(Body/Query/Env):
    - SMOKE_GATEWAY_AUTO_KEY=1
    - GATEWAY_PROFILE_EQUIPMENT_CODE=EQ-GW-001
  기대결과: "[gateway] uplink ok 201"
  PASS/FAIL: PASS
  근거 로그 라인(1~3줄): [gateway] uplink ok 201
  비고: 장비키 자동 발급은 smoke 전용 옵션
```

---

## 실제 테스트 항목 (PLACEHOLDER)

아래 항목들은 Ticket-17.2 구현 후 실제 URL/시나리오에 맞게 채워주세요.

### MES 측 (예시 목록)
- MES-17.2-01: PLACEHOLDER (실제 API 경로 필요)
- MES-17.2-02: PLACEHOLDER

### Gateway 측 (예시 목록)
- GW-17.2-01: PLACEHOLDER (실제 장비/프로파일 확인 필요)
- GW-17.2-02: PLACEHOLDER

## 자동 수집 결과
<!-- AUTO_RESULT_START -->
### 자동 실행 결과 (20251220_175523)

| Status | TestId | Title | SourceLog | EvidenceLine |
|---|---|---|---|---|
| PASS | Ticket-04 | Processes 스모크 완료 | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-04 Processes 스모크 완료 |
| PASS | Ticket-05 | Equipments 스모크 완료 | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-05 Equipments 스모크 완료 |
| PASS | Ticket-06 | Defect Types 스모크 완료 | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-06 Defect Types 스모크 완료 |
| PASS | Ticket-07 | Partners 스모크 완료 | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-07 Partners 스모크 완료 |
| PASS | Ticket-08 | Telemetry 스모크 완료 | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-08 Telemetry 스모크 완료 |
| PASS | Ticket-09 | Telemetry Auth 스모크 완료 | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-09 Telemetry Auth 스모크 완료 |
| PASS | Ticket-09.1 | rotate(1) 새 키 201 확인 | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-09.1 rotate(1) 새 키 201 확인 |
| PASS | Ticket-09.1 | rotate(2) 이전키 401 / 새키 201 확인 | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-09.1 rotate(2) 이전키 401 / 새키 201 확인 |
| PASS | Ticket-09.2 | stable-json canonical 확인(201) | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-09.2 stable-json canonical 확인(201) |
| PASS | Ticket-09.1 | revoke 후 401 확인 | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-09.1 revoke 후 401 확인 |
| PASS | Ticket-09.1 | nonce cleanup 삭제 확인 | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-09.1 nonce cleanup 삭제 확인 |
| PASS | Ticket-09.1 | Telemetry Ops 스모크 완료 | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-09.1 Telemetry Ops 스모크 완료 |
| PASS | Ticket-10 | Work Orders/Results 스모크 완료 | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-10 Work Orders/Results 스모크 완료 |
| PASS | Ticket-11 | Quality Inspections 스모크 완료 | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-11 Quality Inspections 스모크 완료 |
| PASS | Ticket-12 | Quality Check Items 스모크 완료 | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-12 Quality Check Items 스모크 완료 |
| PASS | Ticket-13 | pre: item-category upsert (409) | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-13 pre: item-category upsert (409) |
| PASS | Ticket-13 | pre: item-category list (200) | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-13 pre: item-category list (200) |
| PASS | Ticket-13 | pre: item upsert (409) | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-13 pre: item upsert (409) |
| PASS | Ticket-13 | pre: item list (200) | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-13 pre: item list (200) |
| PASS | Ticket-13 | pre: item-category upsert (409) | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-13 pre: item-category upsert (409) |
| PASS | Ticket-13 | pre: item-category list (200) | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-13 pre: item-category list (200) |
| PASS | Ticket-13 | pre: item upsert (409) | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-13 pre: item upsert (409) |
| PASS | Ticket-13 | pre: item list (200) | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-13 pre: item list (200) |
| PASS | Ticket-13A | : LOT 생성(201/409) (201) | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-13A: LOT 생성(201/409) (201) |
| PASS | Ticket-13A | : VIEWER 생성 차단(403) (403) | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-13A: VIEWER 생성 차단(403) (403) |
| PASS | Ticket-13A | : itemId 없음/타사 400 (400) | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-13A: itemId 없음/타사 400 (400) |
| PASS | Ticket-13B | : 자식 LOT 생성(201/409) (201) | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-13B: 자식 LOT 생성(201/409) (201) |
| PASS | Ticket-13 | pre: COMPANY-B LOT 생성 (201) | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-13 pre: COMPANY-B LOT 생성 (201) |
| PASS | Ticket-13B | : 타사 parentLotNo 차단 400 (400) | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-13B: 타사 parentLotNo 차단 400 (400) |
| PASS | Ticket-13B | : trace 조회(200) (200) | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-13B: trace 조회(200) (200) |
| PASS | Ticket-13 | LOT Trace 스모크 완료 | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-13 LOT Trace 스모크 완료 |
| PASS | Ticket-13.1 | WorkOrder-LOT Link 스모크 완료 | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-13.1 WorkOrder-LOT Link 스모크 완료 |
| PASS | Ticket-14 | Reports 스모크 완료 | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-14 Reports 스모크 완료 |
| PASS | Ticket-15 | Dashboard 스모크 완료 | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-15 Dashboard 스모크 완료 |
| PASS | Ticket-16 | Dashboard KPI 스모크 완료 | ticket17_2-mes-smoke-ps51-20251220_175523.log | [PASS] Ticket-16 Dashboard KPI 스모크 완료 |
| PASS | Ticket-04 | Processes 스모크 완료 | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-04 Processes 스모크 완료 |
| PASS | Ticket-05 | Equipments 스모크 완료 | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-05 Equipments 스모크 완료 |
| PASS | Ticket-06 | Defect Types 스모크 완료 | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-06 Defect Types 스모크 완료 |
| PASS | Ticket-07 | Partners 스모크 완료 | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-07 Partners 스모크 완료 |
| PASS | Ticket-08 | Telemetry 스모크 완료 | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-08 Telemetry 스모크 완료 |
| PASS | Ticket-09 | Telemetry Auth 스모크 완료 | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-09 Telemetry Auth 스모크 완료 |
| PASS | Ticket-09.1 | rotate(1) 새 키 201 확인 | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-09.1 rotate(1) 새 키 201 확인 |
| PASS | Ticket-09.1 | rotate(2) 이전키 401 / 새키 201 확인 | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-09.1 rotate(2) 이전키 401 / 새키 201 확인 |
| PASS | Ticket-09.2 | stable-json canonical 확인(201) | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-09.2 stable-json canonical 확인(201) |
| PASS | Ticket-09.1 | revoke 후 401 확인 | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-09.1 revoke 후 401 확인 |
| PASS | Ticket-09.1 | nonce cleanup 삭제 확인 | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-09.1 nonce cleanup 삭제 확인 |
| PASS | Ticket-09.1 | Telemetry Ops 스모크 완료 | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-09.1 Telemetry Ops 스모크 완료 |
| PASS | Ticket-10 | Work Orders/Results 스모크 완료 | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-10 Work Orders/Results 스모크 완료 |
| PASS | Ticket-11 | Quality Inspections 스모크 완료 | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-11 Quality Inspections 스모크 완료 |
| PASS | Ticket-12 | Quality Check Items 스모크 완료 | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-12 Quality Check Items 스모크 완료 |
| PASS | Ticket-13 | pre: item-category upsert (409) | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-13 pre: item-category upsert (409) |
| PASS | Ticket-13 | pre: item-category list (200) | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-13 pre: item-category list (200) |
| PASS | Ticket-13 | pre: item upsert (409) | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-13 pre: item upsert (409) |
| PASS | Ticket-13 | pre: item list (200) | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-13 pre: item list (200) |
| PASS | Ticket-13 | pre: item-category upsert (409) | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-13 pre: item-category upsert (409) |
| PASS | Ticket-13 | pre: item-category list (200) | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-13 pre: item-category list (200) |
| PASS | Ticket-13 | pre: item upsert (409) | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-13 pre: item upsert (409) |
| PASS | Ticket-13 | pre: item list (200) | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-13 pre: item list (200) |
| PASS | Ticket-13A | : LOT 생성(201/409) (201) | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-13A: LOT 생성(201/409) (201) |
| PASS | Ticket-13A | : VIEWER 생성 차단(403) (403) | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-13A: VIEWER 생성 차단(403) (403) |
| PASS | Ticket-13A | : itemId 없음/타사 400 (400) | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-13A: itemId 없음/타사 400 (400) |
| PASS | Ticket-13B | : 자식 LOT 생성(201/409) (201) | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-13B: 자식 LOT 생성(201/409) (201) |
| PASS | Ticket-13 | pre: COMPANY-B LOT 생성 (201) | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-13 pre: COMPANY-B LOT 생성 (201) |
| PASS | Ticket-13B | : 타사 parentLotNo 차단 400 (400) | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-13B: 타사 parentLotNo 차단 400 (400) |
| PASS | Ticket-13B | : trace 조회(200) (200) | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-13B: trace 조회(200) (200) |
| PASS | Ticket-13 | LOT Trace 스모크 완료 | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-13 LOT Trace 스모크 완료 |
| PASS | Ticket-13.1 | WorkOrder-LOT Link 스모크 완료 | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-13.1 WorkOrder-LOT Link 스모크 완료 |
| PASS | Ticket-14 | Reports 스모크 완료 | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-14 Reports 스모크 완료 |
| PASS | Ticket-15 | Dashboard 스모크 완료 | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-15 Dashboard 스모크 완료 |
| PASS | Ticket-16 | Dashboard KPI 스모크 완료 | ticket17_2-mes-smoke-pwsh-20251220_175523.log | [PASS] Ticket-16 Dashboard KPI 스모크 완료 |
<!-- AUTO_RESULT_END -->



