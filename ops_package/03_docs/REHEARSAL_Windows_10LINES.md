# Windows 리허설 10줄 복붙 명령 세트

아래 10줄을 **그대로 복붙**해서 실행하면 리허설을 1회 완료할 수 있습니다.

---

## 전제

- 레포 경로 예시: `C:\MES\repo`
- NSSM 경로 예시: `C:\tools\nssm\nssm.exe`
- `.env`는 반드시 **운영 서버 값으로 수정**
- 비밀값(키/토큰)은 **화면 공유 금지**

---

## 10줄 복붙 명령 세트

```powershell
cd /d C:\MES\repo
copy .\ops_package\04_templates\env\.env.rehearsal.windows.example .\.env
notepad .\.env
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\install_windows_service.ps1 -NssmPath "C:\tools\nssm\nssm.exe" -ServiceName "MES-WebServer"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\status_windows_service.ps1
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

---

## 실패 시 가장 흔한 3가지 원인과 1줄 조치

1) MES_BASE_URL 미설정 → `.env` 수정 후 재실행  
2) 서비스 미기동 → `restart_windows_service.ps1` 실행  
3) 포트 LISTEN FAIL → `logs\windows_service` 로그 확인
