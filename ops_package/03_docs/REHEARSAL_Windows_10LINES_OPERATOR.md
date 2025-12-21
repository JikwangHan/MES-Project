# Windows 리허설 10줄(운영자용, 조건 분기 포함)

이 문서는 **운영자/재리허설/재점검** 용도입니다.  
이미 설치된 서비스가 있으면 **install을 건너뛰고 status/restart로 분기**합니다.

---

## 전제

- 레포 경로 예시: `C:\MES\repo`
- NSSM 경로 예시: `C:\tools\nssm\nssm.exe`
- 서비스명: `MES-WebServer`
- `.env`는 **존재하면 덮어쓰지 않음**
- 비밀값(키/토큰)은 **화면 공유 금지**
- 캡처 보안 체크리스트: `ops_package/03_docs/CAPTURE_REDACTION_CHECKLIST_1PAGE.md`

---

## 운영자용 10줄(조건 분기 포함)

```powershell
cd /d C:\MES\repo
if (!(Test-Path .\.env)) { copy .\ops_package\04_templates\env\.env.rehearsal.windows.example .\.env }
notepad .\.env
$svc="MES-WebServer"; $nssm="C:\tools\nssm\nssm.exe"; $s=Get-Service -Name $svc -ErrorAction SilentlyContinue
if (-not $s) { powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\install_windows_service.ps1 -NssmPath $nssm -ServiceName $svc } else { powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\status_windows_service.ps1 }
if ((Get-Service -Name $svc).Status -ne "Running") { powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\restart_windows_service.ps1 }
powershell.exe -NoProfile -Command "iwr ($env:MES_BASE_URL + '/health') -UseBasicParsing | Select-Object -Expand StatusCode"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\prepare_capture_session.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\run_ticket_17_2.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\hardening_selfcheck.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\collect_evidence.ps1; powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\build_handover_bundle.ps1 -Version "v0.1"
```

---

## 실행 후 산출물 위치

- 캡처 폴더: `ops_package\05_evidence\captures\<세션ID>\`
- evidence ZIP: `ops_package\05_evidence\evidence_*.zip`
- HANDOVER_BUNDLE ZIP: `ops_package\06_dist\HANDOVER_BUNDLE_*.zip`

## (선택) 캡처 sanity 확인
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\check_capture_sanity.ps1 -SessionId <세션ID>
```

---

## 실패 시 가장 흔한 3가지 원인과 1줄 조치

1) MES_BASE_URL 미설정 → `.env` 수정 후 재실행  
2) 서비스 미기동 → `restart_windows_service.ps1` 실행  
3) 포트 LISTEN FAIL → `logs\windows_service` 로그 확인
