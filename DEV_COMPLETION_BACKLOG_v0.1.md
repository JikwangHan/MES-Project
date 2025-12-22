# DEV_COMPLETION_BACKLOG v0.1

## 범위
- Gateway adapters / Message standard / UI screens
- 운영 산출물(ops_package/SOP/리허설/판정기)은 안정화 상태 유지

## 원칙
1) P0 우선: 운영 필수 기능부터 닫는다.
2) 운영 산출물 변경 최소화: 안정성 유지가 최우선이다.
3) 새 기능은 Ticket 기반으로 자동 테스트에 편입한다.

## 참고 링크
- P0 닫기 1장 체크리스트: P0_CLOSEOUT_CHECKLIST_1PAGE_v0.1.md

## 현 상태 요약(게이트웨이)
- uplink: `edge-gateway/src/uplink/mes_telemetry_client.js`에서 `/api/v1/telemetry/events`로 전송
- 서명/nonce: `x-device-key`, `x-ts`, `x-nonce`, `x-signature`, `x-canonical` 헤더 사용
- 프로파일: `edge-gateway/src/config.js`에서 profile + register map 로드
- 노멀라이즈: `edge-gateway/src/normalizer/normalize.js`에서 telemetry payload 생성
- 원시로그/재시도: `raw_log_store.js`, `retry_queue.js`에 JSON 저장

---

## P0 (출시/운영 필수)

### Gateway (연동 코어)
| 항목 | 수용 기준 | 테스트 방법 | 산출물 |
|---|---|---|---|
| Modbus TCP 어댑터 | 연결/재연결, 타임아웃, 폴링 스케줄 동작 | 샘플 프로파일 + 더미 모드 실행 | `edge-gateway/src/adapters/modbus_tcp.js` |
| Modbus RTU 어댑터 | 포트 설정(baud/parity/stop) 반영 | 샘플 RTU 프로파일 실행 | `edge-gateway/src/adapters/modbus_rtu.js` |
| 레지스터 맵 v0.1 | 주소/타입/스케일/엔디안 매핑 | 샘플 맵 검증 | `edge-gateway/config/register_maps/*.json` |
| 재전송 큐 최소 | uplink 실패 시 큐 적재, 성공 시 정리 | uplink 실패 시나리오 | `edge-gateway/src/queue/retry_queue.js` |
| 표준 노멀라이즈 모델 | 장비 값을 표준 telemetry로 변환 | uplink payload 검증 | `edge-gateway/src/normalizer/normalize.js` |

### 메시지 표준(계약)
| 항목 | 수용 기준 | 테스트 방법 | 산출물 |
|---|---|---|---|
| MES 메시지 v0.2 | 필수/옵션 필드 확정 | Contract test | `docs/telemetry_auth.md` |
| 서명/nonce 계약 | 401/403 규칙 확정 | Ticket-17.2 확장 | `scripts/ops/run_ticket_17_2.ps1` |
| deviceKey 라이프사이클 | 발급/폐기/회전 문서 | 문서 점검 | `docs/ops/OPS_RUNBOOK_SOP_v0.1.md` |

### UI/운영 화면(최소 셋)
| 항목 | 수용 기준 | 테스트 방법 | 산출물 |
|---|---|---|---|
| 장비 등록/키 발급 | 관리자 기업 필터 포함 | UI 수동 검증 | 관련 화면 |
| Telemetry 수신 현황 | 최근 N건 + 필터 | UI 수동 검증 | 관련 화면 |
| 원시로그 조회 | 기간/상태/태그 필터 | UI 수동 검증 | 관련 화면 |

---

## P1 (운영 품질 고도화)
- Gateway 동시성/리소스 제한
- 큐 내구성(재부팅 복구, 백오프, 최대 적재량)
- 레지스터 맵 검증기 + 샘플 템플릿 묶음
- 메시지 스키마 강제 검증(서버/게이트웨이)
- 대시보드(가동/알람/최근 실패) + 간단 리포트/CSV

---

## P2 (기능 확장/상품화)
- OPC-UA, MQTT, 벤더 드라이버(S7 등)
- Edge 분석/룰 엔진
- 고급 리포트/권한 세분/감사 리포트 자동화
