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
