# UI P0 최소 요구사항 (5LINES) v0.1

## 목적
- 실장비 없음 전제에서 “운영자가 장애를 인지하고 증빙을 남길 수 있는 UI”만 닫습니다.
- 원인 분류는 P1로 미룹니다.

## 화면 A: 대시보드 상단 요약
1) 카드 3개 고정: 정상(OK), 경고(WARNING), 미수신(NEVER) 장비 수
2) 기준 시각은 KST로 표시(마지막 집계 시각 1줄)
3) 기준값: TELEMETRY_STALE_MIN 분 초과 시 WARNING
4) WARNING 카드 클릭 시 장비 목록으로 이동하며 status=WARNING 자동 필터 적용
5) WARNING 1대 이상이면 상단 배너 1줄 표시

## 화면 B: 장비 목록
1) 컬럼 4개: 장비명, deviceKey, 최근 수신 시각, 상태 배지
2) 상태 배지: OK / WARNING / NEVER
3) 상태 산출: lastSeenAt 없으면 NEVER, 지연이면 WARNING, 그 외 OK
4) 필터 1개: 상태(ALL/OK/WARNING/NEVER)
5) WARNING/NEVER는 아이콘+굵은 글씨로 강조, 정렬은 WARNING 우선

## 화면 C: 장비 상세
1) 상단 고정: 상태 배지 + 최근 수신 시각(스크롤과 무관)
2) 최근 텔레메트리 20건만 표시(time, metricCount만)
3) 실패 표시는 WARNING/NEVER 상태로만 표현
4) 캡처 포인트: 최근 수신 시각 영역(운영 증빙용)
5) 진입 경로: 목록의 deviceKey 클릭으로만 이동

## P0 원칙(중요)
- 상태는 timestamp 기반으로만 판정하며, 오류 원인 분류는 P0에 넣지 않는다.

## API 계약(P0 최소)
- 장비 목록: GET /api/v1/equipments
  - 필수 필드: id, name, code, deviceKeyId, lastSeenAt, status
  - status: OK/WARNING/NEVER, status 필터는 OK/WARNING/NEVER/ALL만 허용
- 장비 상세 최근 텔레메트리: GET /api/v1/equipments/{id}/telemetry?limit=20
  - 필수 필드: eventTs, metricCount
  - limit 허용 범위: 1..100
- 대시보드 상태 요약: GET /api/v1/dashboard/telemetry-status
  - 필수 필드: counts.ok, counts.warning, counts.never, staleMinutes, lastComputedAt

## 기준값
- TELEMETRY_STALE_MIN 기본값: 5 (분)

## 스모크 실행(복붙)
```
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/smoke_ui_p0.ps1
```

## 실측 PASS 기록
- 실행 시각(KST): 2025-12-22 18:13
- PASS 근거(로그):
  - [PASS] UI-P0-01 equipments list fields (lastSeenAt/status)
  - [PASS] UI-P0-02 dashboard telemetry status counts
  - [PASS] UI-P0-03 equipment telemetry list (eventTs/metricCount)
  - [PASS] UI P0 smoke completed
