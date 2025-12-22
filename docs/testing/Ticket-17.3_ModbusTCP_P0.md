# Ticket-17.3 Modbus TCP (P0) - 실행 체크리스트

## 목표
- Modbus TCP 값을 읽고 표준 telemetry payload로 변환 후 uplink까지 성공
- 현장 장비 없이도 “더미 모드”로 동작 경로 확인

## 사전 조건
- MES 서버 기동: `node src/server.js`
- edge-gateway 의존성 설치(최초 1회): `cd edge-gateway && npm ci`
- 게이트웨이 기준 환경 변수(예시):
  - `MES_BASE_URL=http://localhost:4000`
  - `MES_COMPANY_ID=COMPANY-A`
  - `MES_SIGNING_ENABLED=0` (개발 확인용)
  - `GATEWAY_PROFILE=sample_modbus_tcp`
  - (선택) `MES_SIGNING_ENABLED=1`일 때는 MES_DEVICE_KEY/SECRET 필요

## 테스트 케이스(템플릿)
| TestId | 시나리오 | 입력 | 기대 결과 | PASS 근거 |
|---|---|---|---|---|
| T17.3-01 | Modbus TCP 연결(더미) | sample_modbus_tcp | 연결 성공 로그 | `[PASS] T17.3-01 ...` |
| T17.3-02 | 레지스터 맵 로드 | sample_modbus_tcp_registers.json | metrics 생성 | `[PASS] T17.3-02 ...` |
| T17.3-03 | telemetry 변환 | normalizeTelemetry | payload 생성 | `[PASS] T17.3-03 ...` |
| T17.3-04 | uplink 201 | sendTelemetry | 201 응답 | `[PASS] T17.3-04 ...` |

## 실행 명령(복붙)
```
cd edge-gateway
set GATEWAY_PROFILE=sample_modbus_tcp
node src/index.js --once
```

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
