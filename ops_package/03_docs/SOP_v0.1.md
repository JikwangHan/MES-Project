# 운영 런북(SOP) v0.1 (초보자용, 패키지 기준)

이 문서는 **ops_package 기준 경로**로 작성되었습니다.  
레포 루트에서 실행한다는 전제입니다.

---

## 1) 목적 / 적용 범위

- 목적: 운영 전환 후 **일관된 품질 점검**과 **증빙 기록** 확보
- 범위: MES 서버, Edge Gateway, Ticket-17.2 판정기

---

## 2) 운영 전제 (환경)

### 2-1. 환경 파일 준비

1. 레포 루트에서 `.env.example`을 복사합니다.
```
copy .env.example .env
```
2. `.env` 안의 값을 **내 환경에 맞게 수정**합니다.

### 2-2. 값 우선순위 (중요)

1. **명령행 옵션**
2. **환경변수**
3. **.env 파일**
4. **스크립트 기본값**

### 2-3. 보안 주의사항

아래 값은 **절대 커밋하지 않습니다.**

- `MES_MASTER_KEY`
- `MES_DEVICE_KEY`
- `MES_DEVICE_SECRET`

---

## 3) 일간 점검 (Daily, P0만)

### 3-1. 서버가 이미 실행 중일 때 (권장)

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\run_ticket_17_2.ps1 `
  -RunGatewaySmoke -GatewayAutoKey -GatewayEquipmentCode $env:T17_GATEWAY_EQUIPMENT_CODE
```

### 3-2. 서버 자동 시작 허용(개발/테스트 전용)

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\run_ticket_17_2.ps1 `
  -AutoStartServer -DevMode -RunGatewaySmoke -GatewayAutoKey -GatewayEquipmentCode $env:T17_GATEWAY_EQUIPMENT_CODE
```

합격 기준: **PASS=8, FAIL=0**

---

## 4) 주간 점검 (Weekly)

1. **Daily(P0)** 수행
2. **로그 보관 상태 확인**
   - `logs/` 폴더 용량/보관 기간 확인(예: 30일)
3. **원시 로그(raw log) 확인**
   - `edge-gateway/data/rawlogs` 폴더 확인

---

## 5) 배포 전 점검 (Pre-release, P0+P1)

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\run_ticket_17_2.ps1 `
  -RunGatewaySmoke -GatewayAutoKey -GatewayEquipmentCode $env:T17_GATEWAY_EQUIPMENT_CODE -IncludeP1
```

합격 기준: **PASS=12, FAIL=0**

추가 게이트(있으면 실행):

```
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tools\release-gate.ps1 -ApplyTag -PushTag -ProbeGateway
```

---

## 6) 실패 시 조치(트러블슈팅)

자세한 표는 `ops_package/03_docs/TROUBLESHOOTING.md`를 참고하세요.

---

## 7) 운영 기록(증빙) 규칙

- 로그 파일명은 스탬프가 포함되어 자동 생성됩니다.
- 체크리스트 자동 섹션은 **최신 실행 결과로 갱신**됩니다.
- 배포 전 점검 후 `RELEASE_NOTES.md`에 요약을 남깁니다.
