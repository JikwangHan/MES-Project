# 운영자용 최종 5줄 (리허설 → 캡처 → 번들 → 검증)

이 문서는 **운영 서버 제출 직전**을 5줄 복붙으로 끝내기 위한 운영자용 가이드입니다.

---

## 사전 조건(필수 확인)

- 레포 경로 예시: `C:\MES\repo` (현장 경로로 수정)
- NSSM 경로 예시: `C:\tools\nssm\nssm.exe` (현장 경로로 수정)
- 서비스명: `MES-WebServer` (현재 표준)

보안 주의:
- 캡처 전 **마스킹 체크리스트** 확인 필수  
  `ops_package/03_docs/CAPTURE_REDACTION_CHECKLIST_1PAGE.md`

---

## 5줄 복붙 명령

```powershell
cd /d C:\MES\repo
if (!(Test-Path .\.env)) { Copy-Item .\ops_package\04_templates\env\.env.rehearsal.windows.example .\.env -Force; notepad .\.env }
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\prepare_capture_session.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$svc='MES-WebServer'; $nssm='C:\tools\nssm\nssm.exe'; if (Get-Service -Name $svc -ErrorAction SilentlyContinue) { & .\ops_package\02_scripts\restart_windows_service.ps1 } else { & .\ops_package\02_scripts\install_windows_service.ps1 -NssmPath $nssm -ServiceName $svc }; Start-Sleep -Seconds 2; & .\ops_package\02_scripts\status_windows_service.ps1; & .\scripts\ops\run_ticket_17_2.ps1; & .\ops_package\02_scripts\hardening_selfcheck.ps1; & .\ops_package\02_scripts\build_handover_bundle.ps1 -Version 'v0.1'; $bundle=(Get-ChildItem -Path .\ops_package\06_dist -Filter 'HANDOVER_BUNDLE_*.zip' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1); if ($bundle) { Write-Host ('LATEST_BUNDLE=' + $bundle.Name) } else { Write-Host '[WARN] No HANDOVER_BUNDLE zip found' }; $capRoot='.\ops_package\05_evidence\captures'; $sid=(Get-ChildItem $capRoot -Directory | Sort-Object Name | Select-Object -Last 1).Name; Start-Process explorer.exe (Join-Path $capRoot $sid); Write-Host '이제 캡처 #1~#6을 위 폴더에 저장한 뒤 Enter'; Read-Host"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$capRoot='.\ops_package\05_evidence\captures'; $sid=(Get-ChildItem $capRoot -Directory | Sort-Object Name | Select-Object -Last 1).Name; & .\ops_package\02_scripts\check_capture_sanity.ps1 -SessionId $sid; & .\ops_package\02_scripts\check_handover_bundle_contents.ps1 -SessionId $sid; & .\ops_package\02_scripts\judge_handover_ready.ps1 -SessionId $sid"
```

---

## 참고(실행 중 유의사항)

- 2번째 줄에서 `.env`가 열리면 **값 확인 후 저장**해야 합니다.
- 4번째 줄 실행 후 **탐색기가 열리면** 캡처 #1~#6을 저장하고 Enter를 누릅니다.
- 4번째 줄에 출력되는 `LATEST_BUNDLE=...`가 제출 대상 번들 파일명입니다.
- 번들 폴더 바로 열기(표준): explorer.exe .
- (옵션) 가능하면 explorer.exe /select,"C:\\MES\\repo\\HANDOVER_BUNDLE_..." 로 해당 파일을 선택해 열 수 있습니다.
- 주의: 환경마다 동작 차이가 있으므로 기본은 폴더 열기를 사용합니다.
- 5번째 줄에서 **[PASS] HANDOVER READY**면 제출 확정입니다.
- 5번째 줄에서 **[FAIL]**이면 제출 중단 후 원인을 조치하고 재실행합니다.

