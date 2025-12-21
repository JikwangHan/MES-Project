# 운영 인수인계 패키지 시작 안내 (초보자용)

아래 5단계를 **순서대로** 실행하면 됩니다. 모든 명령은 복붙용입니다.

---

## 1) 환경 파일 만들기

레포 루트에서 `.env.example`을 복사해 `.env`를 만듭니다.

```
copy .env.example .env
```

그리고 `.env` 안의 값을 **내 환경에 맞게 수정**합니다.

---

## 2) Daily(P0) 점검 실행

서버가 이미 실행 중일 때:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\run_ticket_17_2.ps1 `
  -RunGatewaySmoke -GatewayAutoKey -GatewayEquipmentCode $env:T17_GATEWAY_EQUIPMENT_CODE
```

서버 자동 시작 허용(개발/테스트 전용):

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\run_ticket_17_2.ps1 `
  -AutoStartServer -DevMode -RunGatewaySmoke -GatewayAutoKey -GatewayEquipmentCode $env:T17_GATEWAY_EQUIPMENT_CODE
```

합격 기준: PASS=8, FAIL=0

---

## 3) Pre-release(P0+P1) 점검 실행

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\run_ticket_17_2.ps1 `
  -RunGatewaySmoke -GatewayAutoKey -GatewayEquipmentCode $env:T17_GATEWAY_EQUIPMENT_CODE -IncludeP1
```

합격 기준: PASS=12, FAIL=0

---

## 4) 증빙 수집 ZIP 만들기

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\collect_evidence.ps1
```

생성 위치: `ops_package/05_evidence/evidence_YYYYMMDD_HHMM.zip`

---

## 5) 운영 패키지 ZIP 빌드

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\build_ops_package.ps1 -Version "v0.1"
```

생성 위치: `ops_package/06_dist/OPS_Package_v0.1_YYYYMMDD_HHMM.zip`

---

## (선택) Windows 서비스 설치 QuickStart

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\install_windows_service.ps1 `
  -NssmPath "C:\tools\nssm\nssm.exe" -ServiceName "MES-WebServer"
```

서비스 상태 확인:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\status_windows_service.ps1
```

---

## (선택) 운영 하드닝 체크

1페이지 요약: `ops_package/03_docs/HARDENING_1PAGE.md`

자가점검(설정 변경 없음):
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\hardening_selfcheck.ps1
```

---

## 주간 유지보수(로그 정리) 등록

- Windows: `ops_package/04_templates/windows/task_scheduler/weekly_rotate_logs.md`
- Linux: `ops_package/03_docs/INSTALL_Linux.md`의 타이머 등록 섹션

---

## 인수인계 제출 체크리스트

1페이지 문서: `ops_package/03_docs/HANDOVER_SUBMISSION_1PAGE.md`

---

## 운영 서버 리허설(Windows)

- 체크리스트: `ops_package/03_docs/REHEARSAL_Windows_NSSM_SELFCHECK_PASS.md`
- 캡처 인덱스: `ops_package/03_docs/CAPTURE_INDEX_TEMPLATE.md`
- 캡처 마스킹 체크리스트: `ops_package/03_docs/CAPTURE_REDACTION_CHECKLIST_1PAGE.md`
- .env 최소값 가이드: `ops_package/03_docs/ENV_MINIMUM_GUIDE_Windows_Rehearsal.md`
- 10줄 복붙(초보자용): `ops_package/03_docs/REHEARSAL_Windows_10LINES.md`
- 10줄 복붙(운영자용/조건 분기): `ops_package/03_docs/REHEARSAL_Windows_10LINES_OPERATOR.md`
