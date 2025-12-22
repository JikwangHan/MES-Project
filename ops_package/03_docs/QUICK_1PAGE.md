# 운영자 1페이지 요약 (복붙용)

## 1) 환경 준비
```
copy .env.example .env
```

## 2) Daily(P0) 점검
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\run_ticket_17_2.ps1 `
  -RunGatewaySmoke -GatewayAutoKey -GatewayEquipmentCode $env:T17_GATEWAY_EQUIPMENT_CODE
```
합격: PASS=8, FAIL=0

## 3) Pre-release(P0+P1) 점검
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\run_ticket_17_2.ps1 `
  -RunGatewaySmoke -GatewayAutoKey -GatewayEquipmentCode $env:T17_GATEWAY_EQUIPMENT_CODE -IncludeP1
```
합격: PASS=12, FAIL=0

## 4) 증빙 ZIP 수집
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\collect_evidence.ps1
```
생성: `ops_package/05_evidence/evidence_*.zip`

## 5) 운영 패키지 ZIP
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\build_ops_package.ps1 -Version "v0.1"
```
생성: `ops_package/06_dist/OPS_Package_v0.1_*.zip`

## (선택) Windows 서비스 운영
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\install_windows_service.ps1 `
  -NssmPath "C:\tools\nssm\nssm.exe" -ServiceName "MES-WebServer"
```
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\status_windows_service.ps1
```

## (선택) 운영 하드닝 요약
`ops_package/03_docs/HARDENING_1PAGE.md`

자가점검:
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\hardening_selfcheck.ps1
```

## 주간 로그 정리 등록 (요약)
Windows:
`ops_package/04_templates/windows/task_scheduler/weekly_rotate_logs.md`

Linux:
`ops_package/03_docs/INSTALL_Linux.md`의 타이머 등록 섹션

수동 실행:
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\rotate_logs.ps1 -RetentionDays 30 -ArchiveRetentionDays 180 -EvidenceRetentionDays 365 -ArchiveSubdir "logs\\archive\\weekly" -Compress
```

## 인수인계 제출 체크리스트
`ops_package/03_docs/HANDOVER_SUBMISSION_1PAGE.md`

## 운영 서버 리허설(Windows)
`ops_package/03_docs/REHEARSAL_Windows_NSSM_SELFCHECK_PASS.md`
`ops_package/03_docs/CAPTURE_INDEX_TEMPLATE.md`
`ops_package/03_docs/CAPTURE_REDACTION_CHECKLIST_1PAGE.md`
`ops_package/03_docs/ENV_MINIMUM_GUIDE_Windows_Rehearsal.md`
`ops_package/03_docs/REHEARSAL_Windows_10LINES.md` (초보자용)
`ops_package/03_docs/REHEARSAL_Windows_10LINES_OPERATOR.md` (운영자용/조건 분기)
`ops_package/03_docs/REHEARSAL_Windows_5LINES_OPERATOR.md` (운영자용/최종 5줄)
캡처 sanity 확인: `ops_package/02_scripts/check_capture_sanity.ps1`

## 제출 직전 2단계 검증
1) 캡처 6/6 확인:
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\check_capture_sanity.ps1 -SessionId <세션ID>
```
2) 번들 ZIP 6/6 확인:
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\check_handover_bundle_contents.ps1
```

## 최종 제출 판정(1줄)
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ops_package\02_scripts\judge_handover_ready.ps1
```
운영자용 최종 5줄은 마지막 줄에 판정기까지 포함됩니다.
운영자용 5줄 4번째 줄에 LATEST_BUNDLE=...가 출력되면 그 파일이 제출 대상입니다.
필요하면 explorer.exe . 로 번들 위치를 바로 열어 확인하세요.
4번째 줄 실행 직후 COPIED_BUNDLE_PATH 명령으로 경로를 복사해 Ctrl+V로 붙여넣기 하세요.
네트워크 불안정 시: 번들 ZIP + 판정기 PASS로 먼저 제출하고, push는 사후 처리(자세한 내용은 SOP Annex D).

