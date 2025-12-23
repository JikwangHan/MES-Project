# P0 CLOSEOUT CHECKLIST (1PAGE) v0.1

## 목적
- 실장비 없음 전제에서 P0 종료 기준을 1장으로 고정합니다.
- 운영 전환 산출물(ops_package/SOP/리허설/판정기)은 변경하지 않습니다.

## A. 게이트웨이 P0 통과 기준
1) Ticket-17.3 PASS 라인 4개 확보
   - [PASS] Ticket-17.3-01 adapter connect
   - [PASS] Ticket-17.3-02 register map load
   - [PASS] Ticket-17.3-03 normalize payload
   - [PASS] Ticket-17.3-04 uplink
2) 재현성 확인
   - edge-gateway에서 `npm ci` 1회 성공
   - modbus-serial 버전 확인(예: 8.0.23)
3) 증빙
   - docs/testing/Ticket-17.3_ModbusTCP_P0.md에 실행 시각(KST) 및 PASS 라인 4줄 기록
   - (권장) 게이트웨이 once 로그 1개 파일 보관

## B. 표준(정규화 규칙) P0 통과 기준
1) 정규화 payload 필수 필드 확인
   - timestamp, deviceKey(또는 deviceKeyId), metrics, schemaVersion(또는 동등 개념)
2) 의미 고정 1줄
   - “metrics 키명은 UI 표기와 1:1 매핑된다” 등 1줄 명시

## C. UI P0 통과 기준(최소 기능)
1) 장비별 최근 수신 시각 표시
2) 수신 상태(성공/실패) 표시
3) uplink 실패 시 운영자가 인지 가능한 표시 1개
4) Ticket-17.3 재실행 후 “수신 흔적” 화면 캡처 1장 확보

UI P0(최근 수신·상태·실패 표시) 항목은 UI-P0 smoke PASS(장비목록 lastSeenAt/status + 대시보드 counts + 장비상세 telemetry)로 닫힘.

E2E P0 증빙은 scripts/smoke_e2e_p0.ps1 PASS로 닫힘.

## D. PR 합치는 순서(리스크 최소)
1) Gateway PR: Modbus TCP + 시뮬레이터 + Ticket-17.3 증빙
2) Standard PR: 정규화 규칙/스키마 문서
3) UI PR: 최근 수신/상태 표시/실패 표시 최소 3개
4) E2E PR: 시뮬레이터 → gateway once → MES uplink → UI 확인 문서

## 실장비 없음 전제의 증빙 정의
- “시뮬레이터 read 성공 + uplink 201 PASS 라인 확보”를 P0 최소 증빙으로 인정합니다.
