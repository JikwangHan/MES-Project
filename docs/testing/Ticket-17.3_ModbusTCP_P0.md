# Ticket-17.3 Modbus TCP (P0) - 실행 체크리스트

## 목표
- Modbus TCP 값을 읽고 표준 telemetry payload로 변환 후 uplink까지 성공
- 현장 장비 없이도 “시뮬레이터”로 read 성공을 재현

## 사전 조건
- MES 서버 기동: `node src/server.js`
- edge-gateway 의존성 설치(최초 1회): `cd edge-gateway && npm ci`
- Modbus TCP 실연결 테스트용 의존성 설치: `cd edge-gateway && npm install`
- 게이트웨이 기준 환경 변수(예시):
  - `MES_BASE_URL=http://localhost:4000`
  - `MES_COMPANY_ID=COMPANY-A`
  - `MES_SIGNING_ENABLED=0` (개발 확인용)
  - `GATEWAY_PROFILE=sample_modbus_tcp_sim`
  - (선택) `MES_SIGNING_ENABLED=1`일 때는 MES_DEVICE_KEY/SECRET 필요

## 테스트 케이스(템플릿)
| TestId | 시나리오 | 입력 | 기대 결과 | PASS 근거 |
|---|---|---|---|---|
| T17.3-01 | Modbus TCP 연결(시뮬레이터) | sample_modbus_tcp_sim | 연결 성공 로그 | `[PASS] T17.3-01 ...` |
| T17.3-02 | 레지스터 맵 로드 | sample_modbus_tcp_registers.json | metrics 생성 | `[PASS] T17.3-02 ...` |
| T17.3-03 | telemetry 변환 | normalizeTelemetry | payload 생성 | `[PASS] T17.3-03 ...` |
| T17.3-04 | uplink 201 | sendTelemetry | 201 응답 | `[PASS] T17.3-04 ...` |

## 실행 명령(복붙)
### 1) Modbus TCP 시뮬레이터 실행
```
node tools/modbus-sim/server.js --profile tools/modbus-sim/profiles/sample_modbus_tcp_sim.json
```

### 2) 게이트웨이 1회 실행
```
cd edge-gateway
set GATEWAY_PROFILE=sample_modbus_tcp_sim
node src/index.js --once
```

### 3) E2E P0 스모크(게이트웨이 → UI)
```
set MES_BASE_URL=http://localhost:4000
set MES_COMPANY_ID=COMPANY-A
set MES_ROLE=VIEWER
set GATEWAY_PROFILE=sample_modbus_tcp_sim
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/smoke_e2e_p0.ps1
```
※ MES health 200이 아니면 uplink/UI 스모크는 SKIP으로 처리되며, E2E 증빙은 완료되지 않은 것으로 본다.

## 결과 기록
- PASS 근거 예시(로그):
  - `[PASS] Ticket-17.3-01 adapter connect`
  - `[PASS] Ticket-17.3-02 register map load`
  - `[PASS] Ticket-17.3-03 normalize payload`
  - `[PASS] Ticket-17.3-04 uplink`
- FAIL 근거 예시(로그):
  - `[FAIL] Ticket-17.3-01 adapter connect`
  - `[FAIL] Ticket-17.3-04 uplink`
- 필요 시 `docs/testing/Ticket-17.2_Test_Checklist.md`에 참고로 요약

## 실측 PASS 기록
- 실행 시각(KST): 2025-12-22 17:50
- PASS 근거(로그):
  - `[PASS] Ticket-17.3-01 adapter connect`
  - `[PASS] Ticket-17.3-02 register map load`
  - `[PASS] Ticket-17.3-03 normalize payload`
  - `[PASS] Ticket-17.3-04 uplink`

## E2E 증빙(표준 5줄)
### MES 정상 기동 상태
- E2E_META 템플릿(복붙):
  `E2E_META | KST=YYYY-MM-DD HH:mm | Env=OS=____;PS=____;Node=____;MES_BASE_URL=____ | Script=smoke_e2e_p0.ps1@____`
- 예시(값만 교체, 경로/계정/서버명 금지):
  `E2E_META | KST=2025-12-23 16:40 | Env=OS=Windows;PS=7.4;Node=v20.11;MES_BASE_URL=http://localhost:8080 | Script=smoke_e2e_p0.ps1@39ae496`
- 자동 생성(클립보드 복사):
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\e2e\print_e2e_meta.ps1 -Copy`
- 외부 공유 대비(베이스URL 레드랙트):
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\e2e\print_e2e_meta.ps1 -Copy -RedactBaseUrl`
- 실행 시각(KST): 2025-12-23 09:59
```
[PASS] E2E-P0-00 mes health check (200 OK)
[PASS] E2E-P0-01 modbus sim started
[PASS] E2E-P0-02 gateway read+normalize ok (profile=sample_modbus_tcp_sim metrics=3)
[PASS] E2E-P0-04 uplink ok (status=201)
[PASS] E2E-P0-05 ui-p0 smoke ok (equipments, dashboard, telemetry)
```

### 증빙 단일 근거 정책
- 이 섹션이 E2E 증빙의 단일 근거이며, 다른 문서에는 중복 삽입하지 않는다.
- 다른 문서는 이 섹션으로 링크만 유지한다.

## 재현성 확인
- npm ci 완료(KST): 2025-12-22 17:58
- modbus-serial 버전: 8.0.23

## UI 캡처 포인트(P0)
- 장비 목록 화면: 최근 수신 시각 + 상태 배지 노출
- 장비 상세 화면: 상단 고정 상태 배지 + 최근 수신 시각

## 최신 실행 결과 (2026-02-13 KST)
- 실행 시각(KST): 2026-02-13 15:43
- UI P0 smoke:
  - `[PASS] UI-P0-01 equipments list fields (lastSeenAt/status)`
  - `[PASS] UI-P0-02 dashboard telemetry status counts`
  - `[PASS] UI-P0-03 equipment telemetry list (eventTs/metricCount)`
  - `[PASS] UI P0 smoke completed`
- E2E P0 smoke:
  - `[PASS] E2E-P0-00 mes health check (200 OK)`
  - `[PASS] E2E-P0-01 modbus sim started`
  - `[PASS] E2E-P0-02 gateway read+normalize ok (profile=sample_modbus_tcp_sim metrics=3)`
  - `[PASS] E2E-P0-04 uplink ok (status=201)`
  - `[PASS] E2E-P0-05 ui-p0 smoke ok (equipments, dashboard, telemetry)`
