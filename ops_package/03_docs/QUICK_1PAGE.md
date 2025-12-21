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
