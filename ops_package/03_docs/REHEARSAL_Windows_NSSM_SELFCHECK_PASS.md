# Windows 운영 서버 리허설 체크리스트 (NSSM → selfcheck PASS)

이 문서는 **실제 운영 서버에서 Annex C 완료 조건을 모두 PASS**로 만들기 위한 리허설 절차입니다.

---

## 1) 목적 / 범위

- 목적: **NSSM 설치 → selfcheck PASS → Annex C 완료**까지 1회 리허설
- 범위: Windows 운영 서버

---

## 2) 사전 준비

1) 관리자 권한 PowerShell 실행  
2) NSSM 준비 (예: `C:\tools\nssm\nssm.exe`)  
3) 레포 설치 경로 확인 (예: `C:\MES\repo`)  
4) Node 설치 확인:
```
node -v
```

---

## 3) .env 준비 (필수)

```
copy .env.example .env
```

최소값 가이드: `ops_package/03_docs/ENV_MINIMUM_GUIDE_Windows_Rehearsal.md`

캡처 세션 준비(권장):
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\prepare_capture_session.ps1
```

필수 키 확인:
- `MES_BASE_URL`
- `MES_COMPANY_ID`
- `T17_EQUIPMENT_CODE`

주의: **비밀값은 출력/공유 금지**

---

## 4) 단계별 체크리스트 (Annex C 매핑)

### Step A) 서비스 설치(NSSM)

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\install_windows_service.ps1 `
  -NssmPath "C:\tools\nssm\nssm.exe" -ServiceName "MES-WebServer"
```

기대결과: 서비스 등록 완료  
캡처 #1: 서비스 등록 화면 또는 `status_windows_service.ps1` 출력

---

### Step B) 서비스 기동 + health 200 확인

```
nssm start MES-WebServer
```

```
curl.exe -i "$env:MES_BASE_URL/health" -H "x-company-id: $env:MES_COMPANY_ID" -H "x-role: VIEWER"
```

기대결과: 200 OK  
캡처 #2: health 200 결과

---

### Step C) Ticket-17.2 Daily(P0) 실행

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\run_ticket_17_2.ps1
```

기대결과: PASS=8, FAIL=0  
캡처 #3: PASS 근거 라인 3줄

---

### Step D) hardening_selfcheck PASS

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\hardening_selfcheck.ps1
```

기대결과: 필수 항목 PASS  
캡처 #4: PASS 라인 5줄

---

### Step E) evidence ZIP 생성

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\collect_evidence.ps1
```

기대결과: evidence_*.zip 생성  
캡처 #5: 파일 목록 출력

---

### Step F) HANDOVER_BUNDLE 생성

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\build_handover_bundle.ps1 -Version "v0.1"
```

기대결과: HANDOVER_BUNDLE_*.zip 생성  
캡처 #6: 파일 목록 출력

---

## 5) 실패 시 조치(빠른 확인)

- 포트 LISTEN FAIL → 서비스 미기동/포트 확인
- logs/windows_service 없음 → start_mes/로그 경로 확인
- .env 없음 → 파일 위치 재확인
- 서비스 없음 → NSSM 경로 확인 후 재설치

---

## 6) 되돌리기(Backout)

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\uninstall_windows_service.ps1 `
  -NssmPath "C:\tools\nssm\nssm.exe" -ServiceName "MES-WebServer"
```

필요 시 logs 정리 및 .env 보안 보관
