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

---

## 8) Windows 서비스 표준

- Windows 운영 표준은 **NSSM 단일 방식**으로 고정합니다.
- 설치/운영 절차: `ops_package/03_docs/INSTALL_Windows.md`

---

## Annex A. 운영 서버 하드닝 체크리스트 v0.1

요약본: `ops_package/03_docs/HARDENING_1PAGE.md`

### A) 방화벽 / 네트워크
- 인바운드 허용 포트는 **운영 포트만 허용**, 나머지는 차단
- 관리용 접근은 **사내 관리망/VPN**에서만 허용
- health 엔드포인트는 **외부 공개 여부**를 사전에 결정
- Windows 예시:
  - `netsh advfirewall firewall show rule name=all`
  - `Get-NetFirewallRule | Select-Object -First 5`
- Linux 예시:
  - `sudo ufw status`
  - `sudo firewall-cmd --list-all`

### B) 서비스 계정 / 권한 (NSSM)
- 기본 정책: 가능하면 **제한 계정** 사용, LocalSystem은 최소화
- 최소 권한 원칙:
  - 앱 폴더: 읽기/실행
  - logs 폴더: 쓰기
  - ops_package/05_evidence: 쓰기(증빙 생성자만)
  - .env: 읽기(제한)
- 점검 방법(Windows):
  - 서비스 속성 → 로그온 계정 확인
  - `Get-Service MES-WebServer`

### C) 로그 / 증빙 / 환경파일 권한
- `logs/windows_service`는 관리자/서비스 계정만 접근
- `ops_package/05_evidence`는 제출 담당자만 접근
- `.env`는 **읽기 제한** 및 **커밋 금지** 재확인
- 증빙 ZIP에 `.env`가 포함되지 않도록 확인

### D) 포트 / 프로세스 정책
- URL은 항상 `MES_BASE_URL` 기준으로 단일 소스화
- 포트 충돌 시 진단:
  - Windows: `Get-NetTCPConnection -LocalPort <port>`
  - Linux: `ss -lntp | grep <port>`
- 서비스 복구 옵션(재시작 정책) 확인
- Pre-release 점검 시 “방화벽/권한/포트” 항목 추가 확인

---

## Annex B. 로그 보관 및 압축 정책 v0.1

- 원본 logs 보관: **30일**
- 주간 압축: **매주 일요일 03:10**
- 압축 아카이브 보관: **180일**
- evidence ZIP 보관: **365일**
- 디렉터리 규칙:
  - `logs/archive/weekly/` 아래로 주간 압축 저장
  - `ops_package/05_evidence/` 아래 evidence ZIP 저장
- 운영자 체크:
  - 디스크 여유가 **15% 미만이면 경고**로 기록

---

## Annex C. 운영 인수인계 완료 조건(Exit Criteria) v0.1

아래 조건을 모두 만족해야 **인수인계 완료**로 판단합니다.

1) 서비스 설치 완료  
   - Windows: NSSM 서비스 등록 완료  
   - Linux: systemd 서비스/타이머 등록 완료
2) 서비스 기동 후 health 200 확인  
   - 기준: `$env:MES_BASE_URL/health`
3) Ticket-17.2 Daily(P0) 통과  
   - PASS=8, FAIL=0
4) 하드닝 자가점검 통과  
   - `hardening_selfcheck.ps1`에서 **필수 항목 PASS**
5) 제출 체크리스트 충족  
   - `ops_package/03_docs/HANDOVER_SUBMISSION_1PAGE.md` 기준 충족

리허설 문서: `ops_package/03_docs/REHEARSAL_Windows_NSSM_SELFCHECK_PASS.md`

캡처 보안 체크리스트: `ops_package/03_docs/CAPTURE_REDACTION_CHECKLIST_1PAGE.md`
