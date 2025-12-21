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
  - `MES_COMPANY_ID` (기본값: `COMPANY-A`)
  - `T17_EQUIPMENT_CODE` (기본값: `T17-2-EQ-001`)
  - `MES_SIGNING_ENABLED` (서명 테스트 시 `1`)
  - `MES_DEVICE_KEY`, `MES_DEVICE_SECRET` (서명 테스트 시 필요, 값 출력 금지)
  - 운영 안전 옵션:
    - `-AutoStartServer`: 서버가 꺼져 있을 때만 자동 시작/종료
    - `-DevMode`: MES_MASTER_KEY가 없을 때 dev 키를 내부적으로만 설정
    - `-IncludeP1`: P1 확장 테스트까지 포함 실행 (기본은 P0만 실행)

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

---

## Ticket-17.2 실제 테스트 항목 (표)

P1 항목은 `-IncludeP1` 옵션을 줬을 때만 실행됩니다.

| TestId | Priority | Component | URL | Scenario | Auth | Input | ExpectedStatus | PASS/FAIL | EvidenceLine | SourceLog |
|---|---|---|---|---|---|---|---|---|---|---|
| Ticket-17.2-01 | P0 | MES | `http://localhost:4000/health` | 서버 정상 응답 | VIEWER | 없음 | 200 |  |  |  |
| Ticket-17.2-02 | P0 | MES | `POST /api/v1/equipments/:id/device-key` | 장비키 발급 | OPERATOR | equipmentId | 201 |  |  |  |
| Ticket-17.2-03 | P0 | MES | `POST /api/v1/telemetry/events` | 정상 telemetry 업로드 | OPERATOR + 서명헤더 | payload + signature | 201 |  |  |  |
| Ticket-17.2-04 | P0 | MES | `POST /api/v1/telemetry/events` | 서명 불일치 차단 | OPERATOR + 잘못된 signature | payload + bad signature | 401 |  |  |  |
| Ticket-17.2-05 | P0 | MES | `POST /api/v1/telemetry/events` | nonce 재사용 차단 | OPERATOR + 같은 nonce | 2회 전송 | 2번째 401 |  |  |  |
| Ticket-17.2-06 | P0 | MES | `POST /api/v1/telemetry/events` | equipmentCode 누락 차단 | OPERATOR + 서명헤더 | equipmentCode 없음 | 400 |  |  |  |
| Ticket-17.2-07 | P0 | Gateway | `edge-gateway/scripts/smoke-gateway.ps1` | uplink 201 확인 | VIEWER | 자동키 옵션 | 201 |  |  |  |
| Ticket-17.2-08 | P0 | Gateway | `edge-gateway/data/rawlogs` | raw log 생성 확인 | VIEWER | smoke 실행 후 파일 확인 | raw_*.json |  |  |  |
| Ticket-17.2-09 | P1 | MES | `POST /api/v1/telemetry/events` | 잘못된 deviceKeyId 차단 | OPERATOR + 잘못된 deviceKeyId | payload + bad key | 401 |  |  |  |
| Ticket-17.2-10 | P1 | MES | `POST /api/v1/telemetry/events` | 잘못된 ts 형식 차단 | OPERATOR + 서명헤더 | x-ts=abc | 401 |  |  |  |
| Ticket-17.2-11 | P1 | MES | `POST /api/v1/telemetry/events` | 만료 ts 차단 | OPERATOR + 서명헤더 | x-ts=now-1000 | 401 |  |  |  |
| Ticket-17.2-12 | P1 | MES | `POST /api/v1/telemetry/events` | 서명 헤더 누락 차단 | OPERATOR | 서명 헤더 없음 | 401 |  |  |  |

## 자동 수집 결과
<!-- AUTO_RESULT_START -->
### 자동 실행 결과 (20251221_095059)

| Status | TestId | Title | SourceLog | EvidenceLine |
|---|---|---|---|---|
| PASS | Ticket-17.2-01 | health 200 확인 | ticket17_2-cases-20251221_095059.log | [PASS] Ticket-17.2-01 health 200 확인 |
| PASS | Ticket-17.2-02 | device-key 발급 성공 | ticket17_2-cases-20251221_095059.log | [PASS] Ticket-17.2-02 device-key 발급 성공 |
| PASS | Ticket-17.2-03 | telemetry 정상 업로드 201 | ticket17_2-cases-20251221_095059.log | [PASS] Ticket-17.2-03 telemetry 정상 업로드 201 |
| PASS | Ticket-17.2-04 | 서명 불일치 거부 401 | ticket17_2-cases-20251221_095059.log | [PASS] Ticket-17.2-04 서명 불일치 거부 401 |
| PASS | Ticket-17.2-05 | nonce 재사용 거부 401 | ticket17_2-cases-20251221_095059.log | [PASS] Ticket-17.2-05 nonce 재사용 거부 401 |
| PASS | Ticket-17.2-06 | equipmentCode 누락 400 | ticket17_2-cases-20251221_095059.log | [PASS] Ticket-17.2-06 equipmentCode 누락 400 |
| PASS | Ticket-17.2-07 | gateway uplink 201 확인 | ticket17_2-cases-20251221_095059.log | [PASS] Ticket-17.2-07 gateway uplink 201 확인 |
| PASS | Ticket-17.2-08 | raw log 생성 확인 (raw_2025-12-21T00-51-14-504Z.json) | ticket17_2-cases-20251221_095059.log | [PASS] Ticket-17.2-08 raw log 생성 확인 (raw_2025-12-21T00-51-14-504Z.json) |
| PASS | Ticket-17.2-09 | 잘못된 deviceKeyId 거부 401 | ticket17_2-cases-20251221_095059.log | [PASS] Ticket-17.2-09 잘못된 deviceKeyId 거부 401 |
| PASS | Ticket-17.2-10 | 잘못된 ts 거부 401 | ticket17_2-cases-20251221_095059.log | [PASS] Ticket-17.2-10 잘못된 ts 거부 401 |
| PASS | Ticket-17.2-11 | 만료 ts 거부 401 | ticket17_2-cases-20251221_095059.log | [PASS] Ticket-17.2-11 만료 ts 거부 401 |
| PASS | Ticket-17.2-12 | 서명 헤더 누락 거부 401 | ticket17_2-cases-20251221_095059.log | [PASS] Ticket-17.2-12 서명 헤더 누락 거부 401 |
<!-- AUTO_RESULT_END -->












